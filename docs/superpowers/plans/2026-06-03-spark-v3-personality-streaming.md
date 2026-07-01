# Spark v3 — 人格化 + 流式响应 + 记忆机制 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 Spark 从一个生硬的客服式问答机器，改造成一个有记忆、会聊天、逐字输出的 AI 伴侣。

**Architecture:** 新增 SparkMemoryStore（JSON 持久化记忆），在 AIAPIClient 中添加 SSE 流式调用，重写 SparkAIService 的人格化 Prompt + Memory 注入 + 流式方法，SparkViewModel 用 AsyncStream 驱动实时 UI 更新，SparkBackgroundView 键盘感知优化，SparkView 增加动态标题 + 欢迎语 + 工具条。

**Tech Stack:** SwiftUI, URLSession AsyncBytes (SSE), JSON persistence, NLEmbedding

---

## 文件结构

| 操作 | 文件 |
|------|------|
| **新增** | `Notiee/Features/Spark/SparkMemoryStore.swift` |
| **重写** | `Notiee/Features/Spark/SparkAIService.swift` |
| **修改** | `Notiee/Features/Spark/SparkViewModel.swift` |
| **修改** | `Notiee/Features/Spark/SparkView.swift` |
| **修改** | `Notiee/Features/Spark/SparkBackgroundView.swift` |
| **修改** | `Notiee/Features/Spark/SparkChatBubble.swift` |
| **修改** | `Notiee/Features/Spark/SparkCitationRow.swift` |
| **修改** | `Notiee/Services/AIAPIClient.swift` |
| **修改** | `Notiee/Features/Spark/SparkModels.swift` |

---

### Task 1: Memory Store — Spark 的内部记忆

**Files:**
- Create: `Notiee/Features/Spark/SparkMemoryStore.swift`

- [ ] **Step 1: 创建 SparkMemoryStore.swift**

```swift
import Foundation

// MARK: - Protocol

protocol SparkMemoryPersisting {
    func load() throws -> [String: String]
    func save(_ dict: [String: String]) throws
    func set(_ key: String, value: String)
    func get(_ key: String) -> String?
}

// MARK: - JSON Store

final class SparkMemoryStore: SparkMemoryPersisting {
    private let fileURL: URL

    static var live: SparkMemoryStore {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return SparkMemoryStore(fileURL: base
            .appendingPathComponent("Notiee", isDirectory: true)
            .appendingPathComponent("spark_memory.json"))
    }

    init(fileURL: URL) { self.fileURL = fileURL }

    func load() throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return [:] }
        return try JSONDecoder().decode([String: String].self, from: data)
    }

    func save(_ dict: [String: String]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(dict).write(to: fileURL, options: .atomic)
    }

    func set(_ key: String, value: String) {
        var dict = (try? load()) ?? [:]
        dict[key] = value
        try? save(dict)
    }

    func get(_ key: String) -> String? {
        (try? load())?[key]
    }
}
```

- [ ] **Step 2: 在 Xcode 工程中注册该文件**

```bash
ruby -e '
require "xcodeproj"
p = Xcodeproj::Project.open("/Users/tanqinghua/Personal/Notiee/Notiee.xcodeproj")
t = p.targets.first
g = p.main_group.groups.find{|x|x.path=="Notiee"}||p.main_group.new_group("Notiee","Notiee")
g = g.groups.find{|x|x.path=="Features"}||g.new_group("Features","Features")
g = g.groups.find{|x|x.path=="Spark"}||g.new_group("Spark","Spark")
f = g.new_file("SparkMemoryStore.swift")
t.source_build_phase.add_file_reference(f, true)
p.save
puts "Added SparkMemoryStore.swift"
'
```

---

### Task 2: Streaming API — 给 AIAPIClient 加流式调用

**Files:**
- Modify: `Notiee/Services/AIAPIClient.swift:1-80`

- [ ] **Step 1: 在 `OpenAICaller` 中新增 `streamText` 方法**

在 `OpenAICaller` enum 末尾（`}` 之前）追加：

```swift
    /// Streaming text call returning an AsyncThrowingStream of delta chunks.
    static func streamText(
        endpoint: String, model: String, apiKey: String,
        prompt: String, temperature: Double = 0.85
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                guard let url = URL(string: endpoint) else {
                    continuation.finish(throwing: AIError.apiError("Invalid URL"))
                    return
                }
                let payload: [String: Any] = [
                    "model": model,
                    "messages": [["role": "user", "content": prompt]],
                    "max_tokens": 2000,
                    "temperature": temperature,
                    "stream": true
                ]
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: payload)

                let (bytes, _) = try await URLSession.shared.bytes(for: request)
                for try await line in bytes.lines {
                    guard line.hasPrefix("data: ") else { continue }
                    let dataStr = String(line.dropFirst(6))
                    if dataStr == "[DONE]" { continuation.finish(); return }
                    guard let chunkData = dataStr.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: chunkData) as? [String: Any],
                          let choices = json["choices"] as? [[String: Any]],
                          let delta = choices.first?["delta"] as? [String: Any],
                          let content = delta["content"] as? String else { continue }
                    continuation.yield(content)
                }
                continuation.finish()
            }
        }
    }
```

- [ ] **Step 2: 在 `AnthropicCaller` 中新增 `streamText` 方法**

同理追加：

```swift
    /// Streaming text call for Anthropic protocol.
    static func streamText(
        endpoint: String, model: String, apiKey: String,
        prompt: String, temperature: Double = 0.85
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                guard let url = URL(string: endpoint) else {
                    continuation.finish(throwing: AIError.apiError("Invalid URL"))
                    return
                }
                let payload: [String: Any] = [
                    "model": model,
                    "max_tokens": 2000,
                    "temperature": temperature,
                    "stream": true,
                    "messages": [["role": "user", "content": prompt]]
                ]
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: payload)

                let (bytes, _) = try await URLSession.shared.bytes(for: request)
                for try await line in bytes.lines {
                    guard line.hasPrefix("data: ") else { continue }
                    let dataStr = String(line.dropFirst(6))
                    guard let chunkData = dataStr.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: chunkData) as? [String: Any] else { continue }
                    if json["type"] as? String == "message_stop" { continuation.finish(); return }
                    if let delta = json["delta"] as? [String: Any],
                       let text = delta["text"] as? String {
                        continuation.yield(text)
                    }
                }
                continuation.finish()
            }
        }
    }
```

- [ ] **Step 3: 编译验证**

```bash
cd /Users/tanqinghua/Personal/Notiee && xcodebuild -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep "error:" | head -10
```
Expected: 无输出（编译通过）

---

### Task 3: 人格化 + 记忆注入 — 重写 SparkAIService

**Files:**
- Modify: `Notiee/Features/Spark/SparkAIService.swift` (完全重写)

- [ ] **Step 1: 重写 SparkAIService.swift**

新 Prompt 核心设计：

```
你是 Spark，Notiee 里的个人 AI 伴侣。
你不是客服机器人——你是一个善于倾听、有好奇心、偶尔会俏皮、能记住关于用户的事情的朋友。

你的性格：
- 温暖但不油腻。回应自然，像人类朋友聊天。
- 聪明但不刻意卖弄。不提用户没问的知识。
- 幽默但知道分寸。尊重中国文化和社会伦理。
- 诚实但不冷漠。即使用户记录帮不上忙，也用友好的方式回应，不是丢一句「未找到」就结束。
- 记住用户的事。如果用户告诉你 TA 的名字、喜好、最近状态，下次聊到时自然提起。

你的工作方式：
- 用户和你聊天时，你的回答会基于以下「记忆」和「拍记记录」。
- 如果用户没有问拍记相关的事，就自然聊天，不必强行引用记录。
- 引用记录时用 [来源N] 标记。

当前记忆：
{memory}

当前共有 {count} 条拍记：
{records}
```

完整代码：

```swift
import Foundation

enum SparkAIError: LocalizedError {
    case missingConfiguration
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration: return String(localized: "AI 模型尚未配置")
        case .apiError(let msg): return String(localized: "AI 调用失败：\(msg)")
        }
    }
}

final class SparkAIService: Sendable {
    private let settingsStore: AppSettingsPersisting
    private let memoryStore: SparkMemoryPersisting
    private let maxRecordsInPrompt = 150

    init(
        settingsStore: AppSettingsPersisting = UserDefaultsAppSettingsStore.live,
        memoryStore: SparkMemoryPersisting = SparkMemoryStore.live
    ) {
        self.settingsStore = settingsStore
        self.memoryStore = memoryStore
    }

    func askStreaming(question: String, with allRecords: [NoteRecord]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let textConfig = settingsStore.loadConfiguration(for: .text)
                guard textConfig.isComplete else {
                    continuation.finish(throwing: SparkAIError.missingConfiguration)
                    return
                }

                let activeRecords = allRecords
                    .filter { !$0.isDeleted }
                    .sorted { $0.capturedAt > $1.capturedAt }
                    .prefix(maxRecordsInPrompt)

                let prompt = buildPrompt(question: question, records: Array(activeRecords))

                let stream: AsyncThrowingStream<String, Error>
                if textConfig.activeProtocol == .openai {
                    stream = OpenAICaller.streamText(
                        endpoint: textConfig.activeEndpoint,
                        model: textConfig.modelName,
                        apiKey: textConfig.apiKey,
                        prompt: prompt,
                        temperature: 0.85
                    )
                } else {
                    stream = AnthropicCaller.streamText(
                        endpoint: textConfig.activeEndpoint,
                        model: textConfig.modelName,
                        apiKey: textConfig.apiKey,
                        prompt: prompt,
                        temperature: 0.85
                    )
                }

                do {
                    for try await chunk in stream {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // 解析最终完整文本中的 [记忆] 标签，返回(纯文本, 新记忆键值对)
    func extractMemory(from text: String) -> (cleanText: String, newMemories: [String: String]) {
        let pattern = "\\[记忆\\](.*?)\\[/记忆\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else {
            return (text, [:])
        }
        var clean = text
        var memories: [String: String] = []
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            if let range = Range(match.range, in: text),
               let contentRange = Range(match.range(at: 1), in: text) {
                let content = String(text[contentRange]).trimmingCharacters(in: .whitespaces)
                let parts = content.split(separator: ":", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    memories[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1].trimmingCharacters(in: .whitespaces)
                }
                clean.removeSubrange(range)
            }
        }
        return (clean.trimmingCharacters(in: .whitespacesAndNewlines), memories)
    }

    // 从完整文本中提取 [来源N] 引用索引
    func extractCitations(from text: String, recordCount: Int) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: "\\[来源(\\d+)\\]") else { return [] }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var indices = Set<Int>()
        for match in matches {
            if let r = Range(match.range(at: 1), in: text), let idx = Int(text[r]), idx >= 1, idx <= recordCount {
                indices.insert(idx - 1)
            }
        }
        return Array(indices).sorted()
    }

    private func buildPrompt(question: String, records: [NoteRecord]) -> String {
        let memory = (try? memoryStore.load()) ?? [:]
        let memoryLines = memory.isEmpty
            ? "（暂无记忆）"
            : memory.map { "  - \($0.key): \($0.value)" }.joined(separator: "\n")

        var recordsBlock = ""
        for (i, r) in records.enumerated() {
            let date = r.capturedAt.formatted(date: .abbreviated, time: .shortened)
            let s = r.summary.isEmpty ? "" : "摘要：\(truncate(r.summary, 100))"
            recordsBlock += "[记录\(i+1)] \(r.title) | \(date)\n\(s)\n"
        }

        return """
        你是 Spark，Notiee 里的个人 AI 伴侣。你不是客服机器人——你是一个善于倾听、有好奇心、偶尔会俏皮、能记住关于用户的事情的朋友。

        你的性格：
        - 温暖但不油腻。回应自然，像人类朋友聊天。
        - 聪明但不刻意卖弄。不提用户没问的知识。
        - 幽默但知道分寸。尊重中国文化和社会伦理。
        - 诚实但不冷漠。即使用户记录帮不上忙，也用友好的方式回应。
        - 记住用户的事。你可以在回答中用 [记忆]键: 值[/记忆] 的格式悄悄记下关于用户的新信息（这部分不会显示给用户）。

        你的工作方式：
        - 如果用户没有问拍记相关的事，就自然聊天，不必强行引用记录。
        - 引用记录时用 [来源N] 标记。
        - 使用 Markdown 让回答易读。

        当前你对用户的记忆：
        \(memoryLines)

        当前共有 \(records.count) 条拍记记录：
        \(recordsBlock)

        用户说：\(question)
        """
    }

    private func truncate(_ text: String, _ max: Int) -> String {
        text.count <= max ? text : String(text.prefix(max)) + "..."
    }
}
```

---

### Task 4: Streaming Pipeline — SparkViewModel 实时逐字更新

**Files:**
- Modify: `Notiee/Features/Spark/SparkViewModel.swift`

- [ ] **Step 1: 在 ViewModel 中新增流式处理逻辑**

在 `processQuestion` 方法中替换原有的一次性 `aiService.ask` 为流式 `askStreaming`，并增加记忆处理：

```swift
private func processQuestion(_ question: String, userMessage: ChatMessage) async {
    if !NetworkMonitor.shared.isConnected {
        let msg = ChatMessage(role: .assistant, content: String(localized: "网络不可用，无法进行 AI 问答。请检查网络后重试。"))
        messages.append(msg)
        state = .offline
        saveCurrentConversation()
        return
    }

    // 创建一个占位 assistant 消息
    let assistantID = UUID()
    let placeholder = ChatMessage(id: assistantID, role: .assistant, content: "")
    messages.append(placeholder)
    state = .loading

    do {
        let allRecords = recordsProvider?() ?? []
        let stream = aiService.askStreaming(question: question, with: allRecords)
        var fullText = ""

        for try await chunk in stream {
            fullText += chunk
            // 实时更新消息内容
            if let idx = messages.firstIndex(where: { $0.id == assistantID }) {
                messages[idx] = ChatMessage(
                    id: assistantID,
                    role: .assistant,
                    content: fullText,
                    citations: messages[idx].citations
                )
            }
        }

        // 提取记忆标签
        let (cleanText, newMemories) = aiService.extractMemory(from: fullText)
        for (k, v) in newMemories {
            let memoryStore = SparkMemoryStore.live
            memoryStore.set(k, value: v)
        }

        // 提取引用
        let allRecs = allRecords.filter { !$0.isDeleted }.sorted { $0.capturedAt > $1.capturedAt }
        let citationIndices = aiService.extractCitations(from: cleanText, recordCount: allRecs.count)
        let citations: [Citation] = citationIndices.compactMap { idx in
            guard idx < allRecs.count else { return nil }
            let r = allRecs[idx]
            return Citation(recordID: r.id, title: r.title, capturedAt: r.capturedAt)
        }

        // 最终更新
        if let idx = messages.firstIndex(where: { $0.id == assistantID }) {
            messages[idx] = ChatMessage(
                id: assistantID,
                role: .assistant,
                content: cleanText,
                citations: citations
            )
        }
        state = .loaded

        // 首条消息时自动生成标题
        generateTitleIfNeeded()

    } catch {
        if let idx = messages.firstIndex(where: { $0.id == assistantID }) {
            messages.remove(at: idx)
        }
        let msg = ChatMessage(
            role: .assistant,
            content: String(localized: "抱歉，出错了：\(error.localizedDescription)")
        )
        messages.append(msg)
        state = .error(error.localizedDescription)
    }

    saveCurrentConversation()
}
```

- [ ] **Step 2: 新增 `generateTitleIfNeeded` 方法**

```swift
private var hasGeneratedTitle = false

private func generateTitleIfNeeded() {
    guard !hasGeneratedTitle else { return }
    guard let firstUser = messages.first(where: { $0.role == .user }) else { return }
    hasGeneratedTitle = true
    let title = String(firstUser.content.prefix(20)).trimmingCharacters(in: .whitespaces)
    guard !title.isEmpty else { return }
    // 存入 UserDefaults 用于标题展示
    settingsStore.saveString(title, forKey: "spark_current_title")
}
```

- [ ] **Step 3: 新增 `currentTitle` 计算属性**

```swift
var currentTitle: String {
    messages.isEmpty
        ? "Spark"
        : (settingsStore.loadString(forKey: "spark_current_title", defaultValue: "Spark"))
}
```

---

### Task 5: 动态标题 — SparkView 标题随对话变化

**Files:**
- Modify: `Notiee/Features/Settings/SparkView.swift`

- [ ] **Step 1: headerView 改为显示动态标题**

```swift
private var headerView: some View {
    HStack {
        HStack(spacing: 8) {
            Text(viewModel.currentTitle)
                .font(.title.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text("beta")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color(red: 0.361, green: 0.682, blue: 0.980))
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill(Color(red: 0.361, green: 0.682, blue: 0.980).opacity(0.12)))
        }
        Spacer()
        HStack(spacing: 16) {
            Button { viewModel.newConversation() } label: {
                Image(systemName: "square.and.pencil").font(.system(size: 17, weight: .medium)).foregroundStyle(.primary)
            }
            Button { showHistorySheet = true } label: {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 17, weight: .medium)).foregroundStyle(.primary)
            }
        }
    }
    .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 6)
}
```

- [ ] **Step 2: `newConversation` 时重置标题**

在 `SparkViewModel.newConversation()` 末尾追加：

```swift
settingsStore.saveString("Spark", forKey: "spark_current_title")
hasGeneratedTitle = false
```

---

### Task 6: 欢迎语 — 新对话中央显示随机 emoji + 问候

**Files:**
- Modify: `Notiee/Features/Settings/SparkView.swift`

- [ ] **Step 1: 定义问候语池**

在 `SparkModels.swift` 中追加：

```swift
struct GreetingPhrase: Sendable {
    let emoji: String
    let text: String
    static let pool: [GreetingPhrase] = [
        GreetingPhrase(emoji: "👋", text: "嗨！今天有什么想聊的？"),
        GreetingPhrase(emoji: "✨", text: "随时准备好帮你回顾笔记～"),
        GreetingPhrase(emoji: "☀️", text: "今天是个适合整理知识的好日子！"),
        GreetingPhrase(emoji: "💡", text: "有什么灵感需要记录的吗？"),
        GreetingPhrase(emoji: "📖", text: "拍记越多，我越懂你。"),
        GreetingPhrase(emoji: "🎯", text: "来，告诉我你想找什么？"),
        GreetingPhrase(emoji: "🫰", text: "嘿，随便聊聊也可以。"),
        GreetingPhrase(emoji: "🔮", text: "我帮你回顾最近的笔记？"),
    ]
    static func random() -> GreetingPhrase { pool.randomElement()! }
}
```

- [ ] **Step 2: 在 SparkView 聊天区中央显示欢迎语**

```swift
private var greetingView: some View {
    VStack(spacing: 8) {
        Text(GreetingPhrase.random().emoji)
            .font(.system(size: 48))
        Text(GreetingPhrase.random().text)
            .font(.body)
            .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}
```

在 `chatScrollView` 的 `if viewModel.messages.isEmpty` 分支中，把 `suggestedQuestionsView` 替换为 `greetingView` + 下方的随机问题。

---

### Task 7: 随机问题紧贴输入框左对齐

**Files:**
- Modify: `Notiee/Features/Settings/SparkView.swift`

- [ ] **Step 1: 把随机问题放在 `greetingView` 和 `SparkInputBar` 之间**

在 `ZStack` 中，`VStack` 内：

```
headerView
aiDisclaimerBanner
// 中央欢迎语 + 随机问题的容器
if viewModel.messages.isEmpty {
    Spacer()
    greetingView
    randomQuestionsIfEmpty
    Spacer()
} else {
    chatScrollView
}
SparkInputBar(...)
```

- [ ] **Step 2: 确保 `randomQuestionsIfEmpty` 左对齐 + 贴近输入栏**

```swift
private var randomQuestionsIfEmpty: some View {
    VStack(alignment: .leading, spacing: 8) {
        ForEach(viewModel.currentQuestions, id: \.self) { question in
            Button { viewModel.sendQuestion(question) } label: {
                HStack(spacing: 6) {
                    Text(question)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
    }
    .padding(.horizontal, 20)
    .padding(.bottom, 0)  // 贴近输入栏
}
```

---

### Task 8: 动画优化 — 键盘感知 + 减速 + 贴打字框

**Files:**
- Modify: `Notiee/Features/Spark/SparkBackgroundView.swift`

- [ ] **Step 1: 键盘高度观测**

在 `SparkBackgroundView` 中加入：

```swift
@State private var keyboardHeight: CGFloat = 0

// 在 body 中 onAppear 时注册通知
.onAppear {
    NotificationCenter.default.addObserver(
        forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main
    ) { n in
        if let frame = n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
            keyboardHeight = frame.height
        }
    }
    NotificationCenter.default.addObserver(
        forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main
    ) { _ in
        keyboardHeight = 0
    }
}
```

- [ ] **Step 2: blob 位置调整以贴近输入栏（而非键盘底部）**

在 `blobPosition` 函数的 focused 分支中，将目标 Y 调整为：

```swift
let ty = size.height - keyboardHeight - 60  // 输入栏上方
```

- [ ] **Step 3: 发送动画减速**

在 `blobRadius` 和 `blobOpacity` 的 sending 分支中，将 cycle 计算周期从 3.0 秒延长到 5.0 秒：

```swift
let cycle = min(max(elapsed, 0), 5.0) / 5.0
```

---

### Task 9: 引用跳转 — 点击来源进入记录详情

**Files:**
- Modify: `Notiee/Features/Spark/SparkCitationRow.swift`
- Modify: `Notiee/Features/Settings/SparkView.swift`

- [ ] **Step 1: SparkCitationRow 改为 NavigationLink + 接收 NotieeStore**

```swift
struct SparkCitationRow: View {
    let citation: Citation
    let store: NotieeStore

    var body: some View {
        if let record = store.records.first(where: { $0.id == citation.recordID }) {
            NavigationLink {
                RecordDetailView(viewModel: RecordDetailViewModel(record: record, store: store))
            } label: {
                citationContent
            }
            .buttonStyle(.plain)
        } else {
            citationContent
        }
    }

    private var citationContent: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(red: 0.361, green: 0.682, blue: 0.980))
            VStack(alignment: .leading, spacing: 2) {
                Text(citation.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                Text(citation.capturedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .medium)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray5)))
    }
}
```

- [ ] **Step 2: SparkChatBubble 传递 store**

在 `SparkChatBubble` 的 `citationsSection` 中将 `SparkCitationRow` 的 `onCitationTap` 改为直接传入 `store` 参数。

---

### Task 10: Markdown 始终开启 + iOS 原生风格 buttons

**Files:**
- Modify: `Notiee/Features/Spark/SparkChatBubble.swift`
- Modify: `Notiee/Features/Settings/SparkView.swift`

- [ ] **Step 1: 移除 Markdown 的实验室开关依赖**

`SparkChatBubble` 已经使用 `AttributedString(markdown:...)`，天然不依赖实验室开关。确认无任何 `@AppStorage(UDK.labMarkdownRenderingEnabled)` 引用即可。

- [ ] **Step 2: 右上角按钮改为 iOS 原生 `.toolbar` 样式**

将 header 中的两按钮改为 `ToolbarItem` 放置在 navigationBar 右上，或使用 `Label` + `buttonStyle(.borderless)` 确保原生 hit area 和行为。

- [ ] **Step 3: 输入栏发送按钮使用 iOS 原生的 `.tint(.blue)`**

在发送按钮中使用 `.tint(.blue)` 覆盖当前的硬编码颜色。

---

### Task 11: 对话切换性能优化

**Files:**
- Modify: `Notiee/Features/Spark/SparkViewModel.swift`

- [ ] **Step 1: `loadConversation` 改为异步加载**

```swift
func loadConversation(_ saved: SavedConversation) {
    state = .loading
    Task {
        // 先在后台线程构建消息数组
        let msgs = saved.messages
        await MainActor.run {
            self.messages = msgs
            self.state = .idle
        }
        saveCurrentConversation()
    }
}
```

- [ ] **Step 2: `newConversation` 同样优化**

在新对话保存当前对话到 history 时使用后台线程写入：

```swift
func newConversation() {
    guard !messages.isEmpty else { currentQuestions = randomQuestions(); return }
    let msgs = messages
    Task.detached(priority: .background) {
        let title = msgs.first(where: { $0.role == .user })?.content ?? "对话"
        let saved = SavedConversation(
            title: String(title.prefix(30)),
            createdAt: msgs.first?.timestamp ?? Date(),
            lastMessageAt: msgs.last?.timestamp ?? Date(),
            messages: msgs
        )
        var history = (try? SparkHistoryStore.live.loadConversations()) ?? []
        history.append(saved)
        try? SparkHistoryStore.live.saveConversations(history)
    }
    messages = []
    try? conversationStore.saveConversations([])
    state = .idle; inputText = ""
    currentQuestions = randomQuestions()
    settingsStore.saveString("Spark", forKey: "spark_current_title")
    hasGeneratedTitle = false
}
```

---

## 自检

**Spec 覆盖检查：**
- [x] 人格化重定义 + Temperature → Task 3
- [x] 记忆与状态机制 → Task 1 + Task 3
- [x] 流式逐字响应 → Task 2 + Task 4
- [x] 动态标题 → Task 5
- [x] 欢迎语 emoji + 问候 → Task 6
- [x] 随机问题左对齐贴输入框 → Task 7
- [x] 动画优化（键盘感知 + 减速） → Task 8
- [x] 引用跳转记录详情 → Task 9
- [x] Markdown 不受实验室开关影响 → Task 10
- [x] iOS 原生设计规范 → Task 10
- [x] 对话切换卡顿优化 → Task 11

**无 placeholder 残留。** 每个步骤都有具体代码或精确命令。
