import SwiftUI

struct SparkStyleSettingsView: View {
    @AppStorage(UDK.sparkCustomStyle) private var customStyle: String = ""
    @State private var selectedPreset: SparkStylePreset?
    @State private var showAddSheet = false

    enum SparkStylePreset: String, CaseIterable, Identifiable {
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
                Text("设置 Spark 伴侣的聊天风格和语气。留空则使用默认风格。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("预设风格") {
                ForEach(SparkStylePreset.allCases) { preset in
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
        .navigationTitle("Spark聊天风格")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
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
        .onAppear {
            if customStyle.isEmpty {
                selectedPreset = .defaultPreset
            } else if let matched = SparkStylePreset.allCases.first(where: { $0.promptTemplate == customStyle && $0 != .defaultPreset }) {
                selectedPreset = matched
            } else {
                selectedPreset = nil
            }
        }
    }

    // MARK: - Custom Styles Persistence

    private var customStylesList: [CustomStyleItem] {
        guard let data = UserDefaults.standard.data(forKey: UDK.sparkCustomStyles) else { return [] }
        return (try? JSONDecoder().decode([CustomStyleItem].self, from: data)) ?? []
    }

    private func addCustomStyle(title: String, content: String) {
        var list = customStylesList
        list.append(CustomStyleItem(title: title, content: content))
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: UDK.sparkCustomStyles)
        }
        customStyle = content
        selectedPreset = nil
    }

    private func removeCustomStyles(at offsets: IndexSet) {
        var list = customStylesList
        list.remove(atOffsets: offsets)
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: UDK.sparkCustomStyles)
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

#Preview {
    NavigationStack {
        SparkStyleSettingsView()
    }
}
