import SwiftUI
import UniformTypeIdentifiers

struct NottiStyleSettingsView: View {
    @AppStorage(UDK.nottiCustomStyle) private var customStyle: String = ""
    @State private var selectedPreset: NottiStylePreset?
    @State private var showAddSheet = false
    @State private var showSoulImport = false

    enum NottiStylePreset: String, CaseIterable, Identifiable {
        case defaultPreset = "默认"
        case gentle = "温柔知心"
        case sharp = "犀利毒舌"
        case concise = "简洁高效"
        case humorous = "幽默风趣"
        case scholarly = "学究严谨"

        var id: String { rawValue }

        var displayName: String { String(localized: String.LocalizationValue(rawValue)) }

        var promptTemplate: String {
            switch self {
            case .defaultPreset:
                return ""
            case .gentle:
                return "请用温柔、关怀的语气回复，像一位知心好友。多用鼓励和支持的话语，让人感到安心和被理解。"
            case .sharp:
                return "请用犀利、直言不讳的语气回复。可以适当毒舌和吐槽，但要让人感到你是出于关心。可以偶尔翻白眼，但不要人身攻击。"
            case .concise:
                return "回复必须简洁高效，用最少的字传达最多的信息。不要寒暄，不要客套，直接给结论和行动建议。"
            case .humorous:
                return "回复要幽默风趣，可以适当玩梗、开玩笑。让聊天变得轻松愉快，但不要冷嘲热讽或冒犯用户。"
            case .scholarly:
                return "回复要严谨专业，像一位学者。引用事实和数据，用词准确，逻辑清晰。可以适当使用专业术语并加以解释。"
            }
        }
    }

    var body: some View {
        Form {
            Section {
                Text("设置 Notti 伴侣的聊天风格和语气。留空则使用默认风格。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("预设风格") {
                ForEach(NottiStylePreset.allCases) { preset in
                    Button {
                        if selectedPreset == preset {
                            selectedPreset = nil
                            customStyle = ""
                        } else {
                            selectedPreset = preset
                            customStyle = preset.promptTemplate
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(preset.displayName)
                                    .foregroundStyle(.primary)
                                if !preset.promptTemplate.isEmpty {
                                    Text(preset.promptTemplate)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                            if selectedPreset == preset {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(NotieeColors.themed(.blue))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("自定义风格") {
                ForEach(customStylesList, id: \.id) { item in
                    Button {
                        customStyle = item.content
                        selectedPreset = nil
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .foregroundStyle(.primary)
                                    .font(.subheadline.weight(.medium))
                                Text(item.content)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            if customStyle == item.content && !customStyle.isEmpty {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(NotieeColors.themed(.blue))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { indexSet in
                    removeCustomStyles(at: indexSet)
                }

                if customStylesList.isEmpty {
                    Text("暂无自定义风格，点击右上角 + 添加")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .navigationTitle("Notti聊天风格")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showAddSheet = true
                    } label: {
                        Label("新建经典风格", systemImage: "square.and.pencil")
                    }
                    Button {
                        showSoulImport = true
                    } label: {
                        Label("通过 SOUL.md 导入 beta", systemImage: "doc.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .medium))
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddCustomStyleSheet { title, content in
                addCustomStyle(title: title, content: content)
            }
        }
        .sheet(isPresented: $showSoulImport) {
            SoulImportSheet { title, content in
                addCustomStyle(title: title, content: content)
            }
        }
        .onAppear {
            if customStyle.isEmpty {
                selectedPreset = .defaultPreset
            } else if let matched = NottiStylePreset.allCases.first(where: { $0.promptTemplate == customStyle && $0 != .defaultPreset }) {
                selectedPreset = matched
            } else {
                selectedPreset = nil
            }
        }
    }

    // MARK: - Custom Styles Persistence

    private var customStylesList: [CustomStyleItem] {
        guard let data = UserDefaults.standard.data(forKey: UDK.nottiCustomStyles) else { return [] }
        return (try? JSONDecoder().decode([CustomStyleItem].self, from: data)) ?? []
    }

    private func addCustomStyle(title: String, content: String) {
        var list = customStylesList
        list.append(CustomStyleItem(title: title, content: content))
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: UDK.nottiCustomStyles)
        }
        customStyle = content
        selectedPreset = nil
    }

    private func removeCustomStyles(at offsets: IndexSet) {
        var list = customStylesList
        list.remove(atOffsets: offsets)
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: UDK.nottiCustomStyles)
        }
        if customStyle.isEmpty == false && !list.contains(where: { $0.content == customStyle }) {
            customStyle = ""
            selectedPreset = nil
        }
    }
}

// MARK: - Custom Style Data Model

struct CustomStyleItem: Identifiable, Codable {
    let id: UUID
    let title: String
    let content: String

    init(id: UUID = UUID(), title: String, content: String) {
        self.id = id
        self.title = title
        self.content = content
    }
}

// MARK: - Add Custom Style Sheet

struct AddCustomStyleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var content: String = ""
    let onComplete: (String, String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("标题") {
                    TextField("例如：温柔知心", text: $title)
                }
                Section("风格指令") {
                    TextEditor(text: $content)
                        .font(.body)
                        .frame(minHeight: 120)
                        .overlay(alignment: .topLeading) {
                            if content.isEmpty {
                                Text("描述 AI 应该如何回复…")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                }
            }
            .navigationTitle("新建风格")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        let c = content.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty, !c.isEmpty else { return }
                        onComplete(t, c)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - SOUL.md Import Sheet (beta)

/// Import a Notti chat style from a `SOUL.md` file. The uploaded Markdown becomes
/// the style instruction; the H1 (or filename) becomes the title. A style created
/// this way lands in the same custom-styles list as a classic one.
struct SoulImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showFileImporter = false
    @State private var importedTitle: String = ""
    @State private var importedContent: String = ""
    @State private var errorMessage: String?
    let onComplete: (String, String) -> Void

    private var hasImported: Bool { !importedContent.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showFileImporter = true
                    } label: {
                        Label(hasImported ? "重新选择 SOUL.md 文件" : "上传 SOUL.md 文件",
                              systemImage: "arrow.up.doc")
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("导入")
                } footer: {
                    Text("选择一个 .md 文件，其内容将作为 Notti 的风格指令。")
                }

                if hasImported {
                    Section("预览") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(importedTitle)
                                .font(.subheadline.weight(.semibold))
                            Text(importedContent)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(6)
                        }
                    }
                }

                Section("规范参考") {
                    Text(Self.specReference)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("SOUL.md 导入 beta")
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [UTType(filenameExtension: "md") ?? .plainText, .text, .plainText, .data],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        let t = importedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        let c = importedContent.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty, !c.isEmpty else { return }
                        onComplete(t, c)
                        dismiss()
                    }
                    .disabled(!hasImported)
                }
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        errorMessage = nil
        do {
            guard let url = try result.get().first else { return }
            let needsAccess = url.startAccessingSecurityScopedResource()
            defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
            let raw = try String(contentsOf: url, encoding: .utf8)
            let content = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else {
                errorMessage = String(localized: "文件为空，请选择有效的 SOUL.md。")
                return
            }
            importedContent = content
            importedTitle = Self.deriveTitle(from: content, fallback: url.deletingPathExtension().lastPathComponent)
        } catch {
            errorMessage = String(localized: "读取文件失败，请重试。")
        }
    }

    /// Title = first Markdown H1 (`# ...`) if present, else the filename.
    private static func deriveTitle(from content: String, fallback: String) -> String {
        for line in content.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
        }
        return fallback.isEmpty ? String(localized: "SOUL 风格") : fallback
    }

    private static let specReference = """
    SOUL.md 是一份描述 Notti 人格与语气的 Markdown 文件。建议包含：

    # 人格名称
    一句话定位（例如：温柔的学习陪伴者）。

    ## 语气
    描述说话的口吻、情绪、称呼方式。

    ## 行为准则
    - 应该做什么（鼓励、追问、给行动建议…）
    - 不应该做什么（人身攻击、冗长寒暄…）

    ## 示例
    可选：给一两句符合该人格的示范回复。

    整份文件会作为风格指令注入到 Notti 的系统提示中，请用自然语言、避免与隐私/安全指令冲突。
    """
}

#Preview {
    NavigationStack {
        NottiStyleSettingsView()
    }
}
