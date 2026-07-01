# Spark Agent 能力实现方案

> **For agentic workers:** 使用 `subagent-driven-development` 或 `executing-plans` 技能逐任务执行。步骤使用 `- [ ]` 复选框跟踪。

**目标：** 将 Spark 从问答型 AI 升级为具备工具调用、自主执行能力的 Agent，支持 9 个核心工具，包含信任级别体系、操作撤销、协议无关的 LLM 适配。

**架构：** 在现有 Spark MVVM 架构上叠加 Agent 层 —— 新增 `AgentExecutor` 核心回路、`AgentToolRegistry` 工具注册中心、`AgentActionStore` 操作历史持久化，通过 `SparkViewModel.runAgent()` 作为入口。所有工具实现统一的 `AgentTool` 协议，通过依赖注入访问 `NotieeStore` 的 `RecordManager` / `CalendarManager`。

**技术栈：** Swift 6, SwiftUI, Observation (iOS 18+), OpenAI Function Calling + Anthropic Tool Use, JSON File Persistence

---

## Phase 0：基础设施（Blocking Prerequisites）

> **必须最先完成**，所有后续 Phase 依赖此 Phase。

### Task 0.1：AgentTool 协议与数据模型

**创建文件：**
- `Notiee/Features/Spark/Agent/AgentToolProtocol.swift`
- `Notiee/Features/Spark/Agent/AgentModels.swift`

**修改文件：**
- `Notiee/Utils/UserDefaultsKeys.swift` — 新增 Agent 相关 UDK keys

- [ ] **Step 1：创建 `AgentToolProtocol.swift`**

```swift
// Notiee/Features/Spark/Agent/AgentToolProtocol.swift

import Foundation

enum AgentToolPermission: String, Codable, Sendable {
    case read
    case write
    case destructive
}

protocol AgentTool: Sendable {
    var name: String { get }
    var description: String { get }
    var permission: AgentToolPermission { get }
    var parametersSchema: AgentToolParametersSchema { get }
    func execute(parameters: [String: Any]) async throws -> AgentToolResult
}

struct AgentToolParametersSchema: Sendable {
    let type: String = "object"
    let properties: [String: AgentToolProperty]
    let required: [String]
}

struct AgentToolProperty: Sendable {
    let type: String
    let description: String
    let enumValues: [String]?
    let items: AgentToolProperty?
}

struct AgentToolResult: Sendable {
    let success: Bool
    let message: String
    let data: [String: Any]?
    let undoAction: AgentUndoAction?
}

struct AgentUndoAction: Sendable {
    let toolName: String
    let description: String
    let undoParameters: [String: Any]
    let snapshotPath: String?
}
```

- [ ] **Step 2：创建 `AgentModels.swift`**

```swift
// Notiee/Features/Spark/Agent/AgentModels.swift

import Foundation

struct AgentToolResultData: Equatable, Codable, Sendable {
    let success: Bool
    let message: String
    let undoAction: AgentUndoActionData?
}

struct AgentUndoActionData: Equatable, Codable, Sendable {
    let toolName: String
    let description: String
    let undoParametersData: Data
    let snapshotPath: String?

    var undoParametersDict: [String: Any] {
        (try? JSONSerialization.jsonObject(with: undoParametersData) as? [String: Any]) ?? [:]
    }
}

struct AgentAction: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let toolName: String
    let parametersData: Data
    let result: AgentToolResultData
    let executedAt: Date

    var parametersDict: [String: Any] {
        (try? JSONSerialization.jsonObject(with: parametersData) as? [String: Any]) ?? [:]
    }

    init(id: UUID = UUID(), toolName: String, parameters: [String: Any], result: AgentToolResultData, executedAt: Date = Date()) {
        self.id = id
        self.toolName = toolName
        self.parametersData = (try? JSONSerialization.data(withJSONObject: parameters)) ?? Data()
        self.result = result
        self.executedAt = executedAt
    }
}

struct AgentActionSummary: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let actions: [AgentAction]
    let timestamp: Date

    var successCount: Int { actions.filter { $0.result.success }.count }
    var totalCount: Int { actions.count }
}
```

- [ ] **Step 3：在 `UserDefaultsKeys.swift` 中新增 Agent UDK keys**

在 `// MARK: - Spark` 区域新增：

```swift
// MARK: - Spark Agent
static let sparkAgentEnabled = "spark_agent_enabled"
static let sparkAgentTrustLevel = "spark_agent_trust_level"
static let sparkAgentMaxIterations = "spark_agent_max_iterations"
static let sparkAgentMaxToolsPerRound = "spark_agent_max_tools_per_round"
static let sparkAgentUndoTTLMinutes = "spark_agent_undo_ttl_minutes"
static let sparkAgentHistoryRetentionDays = "spark_agent_history_retention_days"
static let sparkAgentTokenWarning = "spark_agent_token_warning"
```

- [ ] **Step 4：编译验证**

```
Product > Build (⌘B)
```

预期：编译成功，无错误。

### Task 0.2：AgentToolRegistry 工具注册中心

**创建文件：**
- `Notiee/Features/Spark/Agent/AgentToolRegistry.swift`

- [ ] **Step 1：创建 `AgentToolRegistry.swift`**

```swift
// Notiee/Features/Spark/Agent/AgentToolRegistry.swift

import Foundation

final class AgentToolRegistry: @unchecked Sendable {
    private let tools: [String: any AgentTool]

    init(tools: [any AgentTool]) {
        var dict: [String: any AgentTool] = [:]
        for tool in tools {
            dict[tool.name] = tool
        }
        self.tools = dict
    }

    func get(_ name: String) -> (any AgentTool)? {
        tools[name]
    }

    func allTools(for trustLevel: AgentTrustLevel) -> [any AgentTool] {
        tools.values.filter { $0.permission.isAllowed(by: trustLevel) }
    }

    func openAITools(for trustLevel: AgentTrustLevel) -> [[String: Any]] {
        allTools(for: trustLevel).map { tool in
            var funcDef: [String: Any] = [
                "name": tool.name,
                "description": tool.description,
                "parameters": Self.buildJSONSchema(from: tool.parametersSchema)
            ]
            return ["type": "function", "function": funcDef]
        }
    }

    func anthropicTools(for trustLevel: AgentTrustLevel) -> [[String: Any]] {
        allTools(for: trustLevel).map { tool in
            [
                "name": tool.name,
                "description": tool.description,
                "input_schema": Self.buildJSONSchema(from: tool.parametersSchema)
            ]
        }
    }

    static func buildJSONSchema(from schema: AgentToolParametersSchema) -> [String: Any] {
        var props: [String: Any] = [:]
        for (key, prop) in schema.properties {
            var p: [String: Any] = ["type": prop.type, "description": prop.description]
            if let ev = prop.enumValues { p["enum"] = ev }
            if let items = prop.items {
                p["items"] = ["type": items.type]
            }
            props[key] = p
        }
        return [
            "type": "object",
            "properties": props,
            "required": schema.required
        ]
    }
}
```

- [ ] **Step 2：编译验证**

预期：编译成功。

### Task 0.3：AgentTrustManager 信任级别管理

**创建文件：**
- `Notiee/Features/Spark/Agent/AgentTrustManager.swift`

- [ ] **Step 1：创建 `AgentTrustManager.swift`**

```swift
// Notiee/Features/Spark/Agent/AgentTrustManager.swift

import Foundation

enum AgentTrustLevel: String, CaseIterable, Codable, Sendable {
    case cautious
    case standard
    case full
}

extension AgentToolPermission {
    func isAllowed(by trustLevel: AgentTrustLevel) -> Bool {
        switch (self, trustLevel) {
        case (.read, _):             return true
        case (.write, .cautious):    return false
        case (.write, _):            return true
        case (.destructive, .full):  return true
        case (.destructive, _):      return false
        }
    }
}

@MainActor
final class AgentTrustManager: ObservableObject {
    @Published var currentLevel: AgentTrustLevel = .standard
    @Published var maxIterations: Int = 5
    @Published var maxToolsPerRound: Int = 3
    @Published var isAgentEnabled: Bool = true

    private let settingsStore: AppSettingsPersisting

    init(settingsStore: AppSettingsPersisting = UserDefaultsAppSettingsStore.live) {
        self.settingsStore = settingsStore
        loadSavedSettings()
    }

    func setLevel(_ level: AgentTrustLevel) {
        currentLevel = level
        settingsStore.saveString(level.rawValue, forKey: UserDefaultsKeys.sparkAgentTrustLevel)
    }

    private func loadSavedSettings() {
        if let raw = settingsStore.loadString(forKey: UserDefaultsKeys.sparkAgentTrustLevel),
           let level = AgentTrustLevel(rawValue: raw) {
            currentLevel = level
        }
        isAgentEnabled = settingsStore.loadBool(forKey: UserDefaultsKeys.sparkAgentEnabled) ?? true
    }
}
```

- [ ] **Step 2：编译验证**

预期：编译成功。

---

## Phase 1：核心回路（P0）

### Task 1.1：AgentActionStore 操作历史与快照管理

**创建文件：**
- `Notiee/Features/Spark/Agent/AgentActionStore.swift`

- [ ] **Step 1：创建 `AgentActionStore.swift`**

```swift
// Notiee/Features/Spark/Agent/AgentActionStore.swift

import Foundation

enum AgentActionStoreError: Error {
    case notUndoable
    case undoExpired
    case toolNotFound
}

final class AgentActionStore {
    private let fileURL: URL
    private let snapshotsDir: URL
    private let queue = DispatchQueue(label: "com.notiee.agent.action.store")

    init(fileURL: URL? = nil, snapshotsDir: URL? = nil) {
        let base = fileURL?.deletingLastPathComponent()
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Notiee", isDirectory: true)
        self.fileURL = fileURL ?? base.appendingPathComponent("AgentActions.json")
        self.snapshotsDir = snapshotsDir ?? base.appendingPathComponent("AgentSnapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: snapshotsDir, withIntermediateDirectories: true)
    }

    func save(_ action: AgentAction) {
        queue.async {
            var actions = self.loadAll()
            actions.append(action)
            self.writeAll(actions)
        }
    }

    func get(_ id: UUID) -> AgentAction? {
        queue.sync {
            loadAll().first { $0.id == id }
        }
    }

    func recent(_ limit: Int = 50) -> [AgentAction] {
        queue.sync {
            Array(loadAll().suffix(limit).reversed())
        }
    }

    // MARK: - Snapshots

    func writeSnapshot(id: UUID, data: Data) throws -> String {
        let path = snapshotsDir.appendingPathComponent("\(id.uuidString).json")
        try data.write(to: path, options: .atomic)
        let fd = open(path.path, O_WRONLY)
        if fd != -1 { fcntl(fd, F_FULLFSYNC); close(fd) }
        return path.path
    }

    func readSnapshot(path: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: path))
    }

    func deleteSnapshot(path: String) throws {
        try FileManager.default.removeItem(at: URL(fileURLWithPath: path))
    }

    func purgeExpiredSnapshots(ttlMinutes: Int) { /* 实现略 */ }

    func recoverOrphanSnapshots() async { /* 实现略 */ }

    // MARK: - Private

    private func loadAll() -> [AgentAction] {
        guard let data = try? Data(contentsOf: fileURL),
              let actions = try? JSONDecoder().decode([AgentAction].self, from: data) else { return [] }
        return actions
    }

    private func writeAll(_ actions: [AgentAction]) {
        guard let data = try? JSONEncoder().encode(actions) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
```

- [ ] **Step 2：编译验证**

### Task 1.2：SparkAIService 新增 agentChat 方法

**修改文件：**
- `Notiee/Features/Spark/SparkAIService.swift` — 新增 `agentChat()` + protocol 扩展

- [ ] **Step 1：在 `SparkAIService.swift` 中新增 Agent 响应模型和 `agentChat` 方法**

在 `SparkAIServing` 协议中新增方法声明，在 `SparkAIService` 扩展中实现：

```swift
// 在 SparkAIServing 协议中新增
func agentChat(messages: [[String: Any]], tools: [[String: Any]]) async throws -> AgentChatResponse

// 新增模型
struct AgentChatResponse: Sendable {
    let text: String
    let toolCalls: [AgentToolCall]
    let tokensUsed: Int
}

struct AgentToolCall: Sendable {
    let id: String
    let name: String
    let parameters: [String: Any]

    var isValid: Bool {
        (try? JSONSerialization.data(withJSONObject: parameters)) != nil
    }
}

// 新增实现
extension SparkAIService {
    func agentChat(messages: [[String: Any]], tools: [[String: Any]]) async throws -> AgentChatResponse {
        // ... OpenAI 和 Anthropic 适配
    }
}
```

- [ ] **Step 2：编译验证**

### Task 1.3：AgentExecutor 核心回路

**创建文件：**
- `Notiee/Features/Spark/Agent/AgentExecutor.swift`

- [ ] **Step 1：创建 `AgentExecutor.swift`**

```swift
// Notiee/Features/Spark/Agent/AgentExecutor.swift

import Foundation

@MainActor
final class AgentExecutor {
    private let aiService: any SparkAIServing
    private let toolRegistry: AgentToolRegistry
    private let actionStore: AgentActionStore
    private let trustManager: AgentTrustManager

    private let maxIterations = 5
    private var currentActions: [AgentAction] = []

    init(aiService: any SparkAIServing, toolRegistry: AgentToolRegistry,
         actionStore: AgentActionStore, trustManager: AgentTrustManager) {
        self.aiService = aiService
        self.toolRegistry = toolRegistry
        self.actionStore = actionStore
        self.trustManager = trustManager
    }

    func run(
        userMessage: String,
        conversationHistory: [ChatMessage],
        onToolCallStart: @escaping (String) -> Void,
        onToolCallEnd: @escaping (AgentAction) -> Void
    ) async throws -> (text: String, summary: String, actionIDs: [UUID]) {
        // ... 核心 Agent 回路
    }

    func undoAction(_ undoAction: AgentUndoActionData) async throws {
        // ... 撤销逻辑
    }
}
```

- [ ] **Step 2：编译验证**

---

## Phase 2：只读工具实现（P1）

### Task 2.1：NoteSearchTool

**创建文件：**
- `Notiee/Features/Spark/Agent/Tools/NoteSearchTool.swift`

### Task 2.2：TodoListTool

**创建文件：**
- `Notiee/Features/Spark/Agent/Tools/TodoListTool.swift`

---

## Phase 3：写入工具实现（P1）

### Task 3.1：NoteCreateTool + NoteUpdateTool

**创建文件：**
- `Notiee/Features/Spark/Agent/Tools/NoteCreateTool.swift`
- `Notiee/Features/Spark/Agent/Tools/NoteUpdateTool.swift`

### Task 3.2：TodoCreateTool + TodoCompleteTool

**创建文件：**
- `Notiee/Features/Spark/Agent/Tools/TodoCreateTool.swift`
- `Notiee/Features/Spark/Agent/Tools/TodoCompleteTool.swift`

### Task 3.3：NoteGetDetailTool + CalendarQueryTool + MemoryManageTool

**创建文件：**
- `Notiee/Features/Spark/Agent/Tools/NoteGetDetailTool.swift`
- `Notiee/Features/Spark/Agent/Tools/CalendarQueryTool.swift`
- `Notiee/Features/Spark/Agent/Tools/MemoryManageTool.swift`

---

## Phase 4：UI 与 ViewModel 集成（P1）

### Task 4.1：SparkViewModel 新增 Agent 方法

**修改文件：**
- `Notiee/Features/Spark/SparkViewModel.swift`

### Task 4.2：SparkView 新增 Agent 开关和工具状态卡片

**修改文件：**
- `Notiee/Features/Spark/SparkView.swift`
- `Notiee/Features/Spark/SparkChatBubble.swift`

---

## Phase 5：Settings 集成与安全护栏（P1）

### Task 5.1：Settings 新增 Agent 配置界面

**修改文件：**
- `Notiee/Features/Settings/SettingsMainView.swift`
- `Notiee/Features/Settings/SettingsViewModel.swift`

### Task 5.2：安全护栏集成

**修改文件：**
- `Notiee/Features/Spark/Agent/AgentExecutor.swift` — 已含权限校验

---

## Phase 6：国际化与打磨（P2）

### Task 6.1：三语 strings 补全（~20条）

**修改文件：**
- `Notiee/en.lproj/Localizable.strings`
- `Notiee/zh-Hans.lproj/Localizable.strings`
- `Notiee/zh-Hant.lproj/Localizable.strings`
