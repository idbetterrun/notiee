import SwiftUI
import Charts


// MARK: - SettingsMainView
struct SettingsMainView: View {
    @StateObject private var viewModel: SettingsViewModel
    @AppStorage(UDK.labMarkdownRenderingEnabled) private var markdownRenderingEnabled = false

    @MainActor
    init(settingsStore: AppSettingsPersisting = UserDefaultsAppSettingsStore.live) {
        _viewModel = StateObject(wrappedValue: SettingsViewModel(settingsStore: settingsStore))
    }

    var body: some View {
        Form {
            Section("常规") {
                Picker("使用场景", selection: $viewModel.scenePreset) {
                    ForEach(ScenePreset.allCases) { preset in
                        Label(preset.displayName, systemImage: preset.iconName)
                            .tag(preset)
                    }
                }

                Picker("App 启动页", selection: $viewModel.defaultTab) {
                    ForEach(AppTab.launchCandidates) { tab in
                        Text(tab.titleKey).tag(tab)
                    }
                }
                .onChange(of: viewModel.defaultTab) { _, _ in viewModel.saveDefaultTab() }
                
                Toggle("显示周数", isOn: $viewModel.showWeekNumbers)
                if viewModel.showWeekNumbers {
                    let dateBinding = Binding<Date>(
                        get: { viewModel.semesterStartDate ?? Date() },
                        set: { viewModel.semesterStartDate = $0 }
                    )
                    DatePicker("第一周开始日期", selection: dateBinding, displayedComponents: .date)
                    Text("修改第一周开始日期后需要重新启动应用才能生效").font(.caption).foregroundColor(.secondary)
                }
            }
            .onChange(of: viewModel.showWeekNumbers) { _, _ in viewModel.saveAll() }
            .onChange(of: viewModel.semesterStartDate) { _, _ in viewModel.saveAll() }
            
            Section("日程") {
                NavigationLink {
                    CalendarSelectionView(viewModel: viewModel)
                } label: {
                    Label("系统日历选择", systemImage: "calendar")
                }
                
                NavigationLink {
                    CourseCalendarSelectionView()
                } label: {
                    Label("课程日历标记", systemImage: "books.vertical.fill")
                }
            }
            
            appearanceSection
            .onChange(of: viewModel.theme) { _, _ in viewModel.saveAll() }
            .onChange(of: viewModel.fontSize) { _, _ in viewModel.saveAll() }
            .onChange(of: viewModel.language) { _, _ in viewModel.saveAll() }
            .onChange(of: viewModel.scenePreset) { _, _ in viewModel.saveAll() }
            .onChange(of: viewModel.accentColor) { _, _ in viewModel.saveAll() }

            Section("大模型") {
                Toggle("启用大模型处理功能", isOn: $viewModel.aiEnabled)

                if viewModel.aiEnabled {
                    Toggle("拍记完后立即分析", isOn: $viewModel.autoProcessAfterCapture)

                    NavigationLink {
                        AIConfigurationView(viewModel: viewModel, kind: .text)
                    } label: {
                        AIConfigurationRow(
                            title: AIModelKind.text.title,
                            systemImage: "text.bubble",
                            configuration: viewModel.textConfiguration
                        )
                    }

                    NavigationLink {
                        AIConfigurationView(viewModel: viewModel, kind: .vision)
                    } label: {
                        AIConfigurationRow(
                            title: AIModelKind.vision.title,
                            systemImage: "eye",
                            configuration: viewModel.visionConfiguration
                        )
                    }

                    NavigationLink {
                        SparkSettingsView(viewModel: viewModel)
                    } label: {
                        Label("Spark", systemImage: "sparkles")
                    }

                    NavigationLink {
                        AIFeatureSettingsView(viewModel: viewModel)
                    } label: {
                        Label("大模型功能", systemImage: "gearshape.2")
                    }

                    Button("测试双端连接") {
                        viewModel.testConnection(for: .text)
                        viewModel.testConnection(for: .vision)
                    }
                    if viewModel.textConnectionTestStatus != .idle {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("文本模型：").font(.caption).foregroundStyle(.secondary)
                            ConnectionStatusView(status: viewModel.textConnectionTestStatus)
                        }
                    }
                    if viewModel.visionConnectionTestStatus != .idle {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("视觉模型：").font(.caption).foregroundStyle(.secondary)
                            ConnectionStatusView(status: viewModel.visionConnectionTestStatus)
                        }
                    }

                    DisclosureGroup("官方帮助文档") {
                        Link("阿里云百炼文档", destination: URL(string: "https://help.aliyun.com/zh/model-studio/")!)
                        Link("火山引擎文档", destination: URL(string: "https://www.volcengine.com/docs/82379/1399009")!)
                        Link("DeepSeek 文档", destination: URL(string: "https://api-docs.deepseek.com/zh-cn/")!)
                        Link("MiniMax 文档", destination: URL(string: "https://platform.minimaxi.com/docs/guides/text-generation")!)
                    }
                }
            }
            .onChange(of: viewModel.aiEnabled) { _, _ in viewModel.saveAll() }
            .onChange(of: viewModel.autoProcessAfterCapture) { _, _ in viewModel.saveAll() }
            
            Section("通知") {
                Toggle("启用日程提醒", isOn: $viewModel.notificationEnabled)
                if viewModel.notificationEnabled {
                    Picker("提前时间", selection: $viewModel.notificationAdvanceTime) {
                        Text("准点提醒").tag(0)
                        Text("5 分钟前").tag(5)
                        Text("10 分钟前").tag(10)
                        Text("20 分钟前").tag(20)
                        Text("30 分钟前").tag(30)
                        Text("45 分钟前").tag(45)
                        Text("1 小时前").tag(60)
                        Text("2 小时前").tag(120)
                    }
                }
                Toggle("启用日程实时活动", isOn: $viewModel.liveActivityEnabled)

                Picker("Token 提醒阈值", selection: $viewModel.tokenWarningThreshold) {
                    Text("不提醒").tag(0)
                    Text("1,000").tag(1000)
                    Text("5,000").tag(5000)
                    Text("10,000").tag(10000)
                    Text("50,000").tag(50000)
                }
            }
            .onChange(of: viewModel.notificationEnabled) { _, _ in viewModel.saveAll() }
            .onChange(of: viewModel.notificationAdvanceTime) { _, _ in viewModel.saveAll() }
            .onChange(of: viewModel.liveActivityEnabled) { _, _ in viewModel.saveAll() }
            .onChange(of: viewModel.tokenWarningThreshold) { _, _ in viewModel.saveAll() }

            Section("高级设置") {
                NavigationLink {
                    CustomModelsListView(viewModel: viewModel)
                } label: {
                    Label("管理自定义模型", systemImage: "slider.horizontal.3")
                }
            }
            
            Section("关于") {
                NavigationLink {
                    AboutNotieeView()
                } label: {
                    HStack {
                        Text("关于 Notiee")
                        Spacer()
                    }
                }
                
                NavigationLink {
                    OpenSourceAcknowledgmentsView()
                } label: {
                    Text("开源声明")
                }
            }
        }
        .navigationTitle("设置")
    }

    // MARK: - Extracted Sections

    private var appearanceSection: some View {
        Section("外观") {
            Picker("颜色主题", selection: $viewModel.theme) {
                Text("浅色").tag("light")
                Text("深色").tag("dark")
                Text("跟随系统").tag("system")
            }

            Picker("主题色", selection: $viewModel.accentColor) {
                AccentColorOption(color: Color.white, label: "默认", isSystemDefault: true).tag("default")
                AccentColorOption(color: NotieeColors.primary, label: "Notiee", isSystemDefault: false).tag("notiee")
            }

            Picker("字体大小", selection: $viewModel.fontSize) {
                Text("小").tag("small")
                Text("中 (默认)").tag("medium")
                Text("大").tag("large")
                Text("超大").tag("extraLarge")
            }

            Picker("语言切换", selection: $viewModel.language) {
                Text("跟随系统").tag("system")
                Text("简体中文").tag("zh-Hans")
                Text("繁體中文").tag("zh-Hant")
                Text("English").tag("en")
            }
            Text("切换语言后需要重新启动应用才能生效").font(.caption).foregroundColor(.secondary)

            Toggle(isOn: $markdownRenderingEnabled) {
                Label("Markdown 渲染", systemImage: "m.square")
            }
            Text("开启后，记录详情页若包含 Markdown 语法，将渲染为样式化排版。").font(.caption).foregroundColor(.secondary)
        }
    }

}


// MARK: - Helpers

private struct AccentColorOption: View {
    let color: Color
    let label: String
    let isSystemDefault: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 14, height: 14)
            if isSystemDefault {
                Circle()
                    .stroke(.gray.opacity(0.4), lineWidth: 1)
                    .frame(width: 14, height: 14)
            }
            Text(label)
        }
    }
}
