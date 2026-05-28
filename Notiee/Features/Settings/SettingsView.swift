import SwiftUI
import Charts

// MARK: - MeView
struct MeView: View {
    let settingsStore: AppSettingsPersisting
    @ObservedObject var store: NotieeStore

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        LoginView()
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .frame(width: 50, height: 50)
                                .foregroundColor(.accentColor)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("登录您的 TomaGo 账户")
                                    .font(.headline)
                                    .foregroundColor(.primary)

                                Text("开启多端同步与高级功能")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                }
                
                Section {
                    NavigationLink {
                        AllSchedulesView(store: store)
                    } label: {
                        Label("全部日程", systemImage: "calendar")
                            .foregroundColor(NotieeColors.themed(.orange))
                    }
                    
                    NavigationLink {
                        ImportScheduleView(store: store)
                    } label: {
                        Label("导入日程", systemImage: "square.and.arrow.down")
                            .foregroundColor(NotieeColors.themed(.green))
                    }
                }
                
                Section {
                    NavigationLink {
                        ReviewView(store: store)
                    } label: {
                        Label("回顾", systemImage: "chart.pie.fill")
                            .foregroundColor(NotieeColors.themed(.blue))
                    }
                }
                
                Section {
                    NavigationLink {
                        BackupRestoreView(store: store)
                    } label: {
                        Label("备份与恢复", systemImage: "arrow.triangle.2.circlepath.doc.on.clipboard")
                            .foregroundColor(NotieeColors.themed(.blue))
                    }
                }
                
                Section {
                    NavigationLink {
                        LabFeaturesView(store: store)
                    } label: {
                        Label("实验室功能", systemImage: "flask.fill")
                            .foregroundColor(NotieeColors.themed(.purple))
                    }
                }
                
                Section {
                    NavigationLink {
                        SettingsMainView(settingsStore: settingsStore)
                    } label: {
                        Label("设置", systemImage: "gearshape.fill")
                            .foregroundColor(NotieeColors.themed(.gray))
                    }
                }
            }
            .navigationTitle("我")
        }
    }
}

// MARK: - ReviewView
struct ReviewView: View {
    @ObservedObject var store: NotieeStore
    @State private var selectedRange: TimeRange = .today

    @AppStorage("notiee.tokenWarningThreshold") private var tokenWarningThreshold: Int = 0
    @AppStorage("notiee.accumulatedDeletedTokens") private var accumulatedDeletedTokens: Int = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Picker("时间范围", selection: $selectedRange) {
                    ForEach(TimeRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                VStack(spacing: 8) {
                    Text("预估 Token 消耗")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    let currentTokens = store.totalTokens(in: selectedRange)
                    Text("\(currentTokens)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(currentTokens >= tokenWarningThreshold && tokenWarningThreshold > 0 ? .orange : .accentColor)

                    Text(tokenComparisonText(for: currentTokens))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.vertical)

                if store.totalTokens(in: selectedRange) >= tokenWarningThreshold && tokenWarningThreshold > 0 {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Token 消耗已超提醒阈值 (\(tokenWarningThreshold) tk)")
                            .font(.caption)
                    }
                    .foregroundColor(.orange)
                    .padding(.horizontal)
                }

                let chartData = tokenDataByEvent()
                if !chartData.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("按日程消耗占比")
                            .font(.headline)
                            .padding(.horizontal)

                        Chart(chartData) { data in
                            SectorMark(
                                angle: .value("Tokens", data.tokens),
                                innerRadius: .ratio(0.6),
                                angularInset: 1.5
                            )
                            .foregroundStyle(by: .value("日程", data.eventName))
                        }
                        .frame(height: 250)
                        .padding()
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }
                }

                let topRecords = topRecordsByToken()
                if !topRecords.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("最耗 Token 的记录 (Top 5)")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(Array(topRecords.enumerated()), id: \.element.id) { index, record in
                            HStack {
                                Text("\(index + 1)")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                    .frame(width: 24)

                                VStack(alignment: .leading) {
                                    Text(record.title)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    Text(record.capturedAt.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Text("\(record.tokenUsage) tk")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.orange)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .cornerRadius(10)
                            .padding(.horizontal)
                        }
                    }
                }

                HStack {
                    Image(systemName: "trash.fill")
                        .foregroundColor(.secondary)
                    Text("已删除记录累计 Token 消耗（含彻底删除）")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(accumulatedDeletedTokens) tk")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)

                Text("声明：以上 Token 数仅为本地根据返回结果的粗略统计，不保证百分百与最终云端扣费结果一致。")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
            .padding(.vertical)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("使用回顾")
    }

    private func tokenComparisonText(for tokens: Int) -> String {
        switch tokens {
        case 0:
            return "还没有消耗 Token 哦，快去拍记吧！"
        case 1..<10_000:
            return "大约相当于写了一篇小短文的数量。"
        case 10_000..<100_000:
            return "大约相当于读完了一本薄薄的杂志。"
        case 100_000..<500_000:
            return "大约相当于一两部中篇小说的字数啦！"
        case 500_000..<1_000_000:
            return "大概花了一本《西游记》的 Token 数咯！"
        default:
            return "天哪！这相当于读完了好几本大部头巨著！"
        }
    }

    private func topRecordsByToken() -> [NoteRecord] {
        let records = store.records(in: selectedRange)
        return Array(records.sorted(by: { $0.tokenUsage > $1.tokenUsage }).prefix(5))
    }

    struct EventTokenData: Identifiable {
        let id = UUID()
        let eventName: String
        let tokens: Int
    }

    private func tokenDataByEvent() -> [EventTokenData] {
        let records = store.records(in: selectedRange)
        var dict: [String: Int] = [:]

        for record in records {
            let name: String
            if let eventID = record.eventID, let event = store.events.first(where: { $0.id == eventID }) {
                name = event.title
            } else {
                name = "未分类"
            }
            dict[name, default: 0] += record.tokenUsage
        }

        return dict.map { EventTokenData(eventName: $0.key, tokens: $0.value) }
            .sorted(by: { $0.tokens > $1.tokens })
    }
}

// MARK: - SettingsMainView
struct SettingsMainView: View {
    @StateObject private var viewModel: SettingsViewModel

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
                    Text(AppTab.today.titleKey).tag(AppTab.today)
                    Text(AppTab.capture.titleKey).tag(AppTab.capture)
                    Text(AppTab.records.titleKey).tag(AppTab.records)
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
            
            Section("外观") {
                Picker("颜色主题", selection: $viewModel.theme) {
                    Text("浅色").tag("light")
                    Text("深色").tag("dark")
                    Text("跟随系统").tag("system")
                }

                Picker("主题色", selection: $viewModel.accentColor) {
                    HStack(spacing: 6) {
                        Circle().fill(.white).frame(width: 14, height: 14).overlay(Circle().stroke(.gray.opacity(0.4), lineWidth: 1))
                        Text("默认")
                    }.tag("default")
                    HStack(spacing: 6) {
                        Circle().fill(NotieeColors.primary).frame(width: 14, height: 14)
                        Text("Notiee")
                    }.tag("notiee")
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
            }
            .onChange(of: viewModel.theme) { _, _ in viewModel.saveAll() }
            .onChange(of: viewModel.fontSize) { _, _ in viewModel.saveAll() }
            .onChange(of: viewModel.language) { _, _ in viewModel.saveAll() }
            .onChange(of: viewModel.scenePreset) { _, _ in viewModel.saveAll() }
            .onChange(of: viewModel.accentColor) { _, _ in viewModel.saveAll() }

            Section("大模型") {
                Toggle("启用大模型处理功能", isOn: $viewModel.aiEnabled)
                
                if viewModel.aiEnabled {
                    Toggle("摘要 (较低消耗)", isOn: $viewModel.aiEnableSummary)
                    Toggle("详细内容 (极高消耗)", isOn: $viewModel.aiEnableDetailedContent)
                    Toggle("待办事项 (较低消耗)", isOn: $viewModel.aiEnableTodos)
                    
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
            .onChange(of: viewModel.aiEnableSummary) { _, _ in viewModel.saveAll() }
            .onChange(of: viewModel.aiEnableDetailedContent) { _, _ in viewModel.saveAll() }
            .onChange(of: viewModel.aiEnableTodos) { _, _ in viewModel.saveAll() }
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
}

// MARK: - CustomModelsListView
struct CustomModelsListView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var showingAddSheet = false
    @State private var editingModel: CustomAIModel?

    var body: some View {
        List {
            if viewModel.customModels.isEmpty {
                Section {
                    Text("暂无自定义模型，点击下方按钮添加。")
                        .foregroundColor(.secondary)
                }
            } else {
                ForEach(viewModel.customModels) { model in
                    Button {
                        editingModel = model
                        showingAddSheet = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.name)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                HStack {
                                    Text(model.kind.title)
                                        .font(.caption)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.accentColor.opacity(0.1))
                                        .foregroundColor(.accentColor)
                                        .cornerRadius(4)
                                    
                                    Text(model.protocolType.rawValue)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.footnote)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .onDelete(perform: deleteModels)
            }
        }
        .navigationTitle("管理自定义模型")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    editingModel = nil
                    showingAddSheet = true
                }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            CustomModelEditSheet(
                model: editingModel,
                onSave: { newModel in
                    if let index = viewModel.customModels.firstIndex(where: { $0.id == newModel.id }) {
                        viewModel.customModels[index] = newModel
                    } else {
                        viewModel.customModels.append(newModel)
                    }
                    viewModel.saveAll()
                }
            )
        }
    }
    
    private func deleteModels(at offsets: IndexSet) {
        viewModel.customModels.remove(atOffsets: offsets)
        viewModel.saveAll()
    }
}

struct CustomModelEditSheet: View {
    @Environment(\.dismiss) var dismiss
    
    let model: CustomAIModel?
    let onSave: (CustomAIModel) -> Void
    
    @State private var name: String = ""
    @State private var kind: AIModelKind = .text
    @State private var protocolType: AIProtocol = .openai
    @State private var endpoint: String = ""
    @State private var modelIdentifier: String = ""
    @State private var apiKey: String = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("基础信息") {
                    TextField("名称 (如: 我的本地 Qwen)", text: $name)
                    Picker("类型", selection: $kind) {
                        Text(AIModelKind.text.title).tag(AIModelKind.text)
                        Text(AIModelKind.vision.title).tag(AIModelKind.vision)
                    }
                    Picker("协议", selection: $protocolType) {
                        Text("OpenAI").tag(AIProtocol.openai)
                        Text("Anthropic").tag(AIProtocol.anthropic)
                    }
                }
                
                Section("连接配置") {
                    TextField("Endpoint (如: https://api.openai.com/v1/chat/completions)", text: $endpoint)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    TextField("Model ID (如: gpt-4o)", text: $modelIdentifier)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    SecureField("API Key", text: $apiKey)
                }
            }
            .navigationTitle(model == nil ? "添加模型" : "编辑模型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let newModel = CustomAIModel(
                            id: model?.id ?? UUID(),
                            name: name.isEmpty ? "未命名模型" : name,
                            kind: kind,
                            endpoint: endpoint,
                            protocolType: protocolType,
                            modelIdentifier: modelIdentifier,
                            apiKey: apiKey
                        )
                        onSave(newModel)
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let model = model {
                    name = model.name
                    kind = model.kind
                    protocolType = model.protocolType
                    endpoint = model.endpoint
                    modelIdentifier = model.modelIdentifier
                    apiKey = model.apiKey
                }
            }
        }
    }
}

// MARK: - AIConfigurationView
struct AIConfigurationView: View {
    @ObservedObject var viewModel: SettingsViewModel
    let kind: AIModelKind

    var body: some View {
        Form {
            if configuration.wrappedValue.providerType == .custom {
                Section {
                    Text("当前正在使用自定义大模型，请前往“高级设置 -> 管理自定义模型”中修改配置。如果要换回内置服务商，请在下方重新选择。")
                        .foregroundStyle(.orange)
                }
            }
            
            Section("服务商") {
                Picker("选择供应商", selection: configuration.providerType) {
                    if configuration.wrappedValue.providerType == .custom {
                        Text("自定义配置").tag(AIProviderType.custom)
                    }
                    ForEach(AIProviderType.allCases.filter { supports(provider: $0, for: kind) && $0 != .custom }) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .onChange(of: configuration.wrappedValue.providerType) { _, _ in
                    let currentProvider = configuration.wrappedValue.providerType
                    if currentProvider != .custom {
                        if let firstModel = currentProvider.predefinedModels.first {
                            configuration.wrappedValue.modelName = firstModel
                        } else {
                            configuration.wrappedValue.modelName = ""
                        }
                    }
                }
            }

            if configuration.wrappedValue.providerType != .custom {
                Section("模型设置") {
                    let currentProvider = configuration.wrappedValue.providerType
                    if !currentProvider.predefinedModels.isEmpty {
                        Picker("模型名称", selection: configuration.modelName) {
                            ForEach(currentProvider.predefinedModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                    } else {
                        TextField(currentProvider.isEndpointIdRequired ? "接入点 ID (ep-xxxxxx)" : "模型名称", text: configuration.modelName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    
                    SecureField("API Key", text: configuration.apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                if configuration.wrappedValue.providerType.isEndpointIdRequired {
                    Section {
                        Text("火山方舟要求传入您创建的专属接入点 ID (Endpoint ID，以 ep- 开头)，而不是模型原始名称。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button("保存配置") {
                        saveConfiguration()
                    }
                }
            }
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var configuration: Binding<AIModelConfiguration> {
        switch kind {
        case .text:
            $viewModel.textConfiguration
        case .vision:
            $viewModel.visionConfiguration
        }
    }
    
    private func supports(provider: AIProviderType, for kind: AIModelKind) -> Bool {
        if provider == .custom { return true }
        switch kind {
        case .text:
            return [.qwenText, .doubaoText, .deepseek, .minimax].contains(provider)
        case .vision:
            return [.qwenVision, .doubaoVision].contains(provider)
        }
    }

    private func saveConfiguration() {
        switch kind {
        case .text:
            viewModel.saveTextConfiguration()
        case .vision:
            viewModel.saveVisionConfiguration()
        }
    }
}

// MARK: - Components
private struct AIConfigurationRow: View {
    let title: String
    let systemImage: String
    let configuration: AIModelConfiguration

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(configuration.isComplete ? .green : .secondary)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)

                Text(configuration.isComplete ? configuration.modelName : "未配置")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ConnectionStatusView: View {
    let status: AIConnectionTestStatus

    var body: some View {
        switch status {
        case .idle:
            Text("点击“测试连接”验证配置是否可用。")
                .foregroundStyle(.secondary)
        case .testing:
            HStack(spacing: 8) {
                ProgressView()
                Text("正在连接 API 并发送测试请求...")
                    .foregroundStyle(.secondary)
            }
        case .success(let message):
            Label(message, systemImage: "checkmark.circle")
                .foregroundStyle(.green)
                .textSelection(.enabled)
        case .failure(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Calendar Selection

struct CalendarSelectionView: View {
    @ObservedObject var viewModel: SettingsViewModel
    
    var body: some View {
        Form {
            Section {
                VStack(spacing: 16) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 48))
                        .foregroundColor(NotieeColors.themed(.orange))
                        .padding(.top, 8)
                    
                    Text("日程读取设置")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            
            Section {
                if viewModel.availableCalendars.isEmpty {
                    Text("未找到可用的系统日历，请先在系统设置中授权访问。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(viewModel.availableCalendars, id: \.calendarIdentifier) { calendar in
                        Button {
                            viewModel.toggleCalendar(calendar.calendarIdentifier)
                        } label: {
                            HStack {
                                Circle()
                                    .fill(Color(cgColor: calendar.cgColor))
                                    .frame(width: 12, height: 12)
                                Text(calendar.title)
                                    .foregroundColor(.primary)
                                Spacer()
                                if viewModel.selectedCalendarIDs.contains(calendar.calendarIdentifier) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
            } footer: {
                Text("取消勾选某个日历后，Notiee 将不再读取该日历中的日程。系统日历（如节假日、生日等）默认显示在 Today 页面。")
            }
        }
        .navigationTitle("日程")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.loadCalendarSelection()
        }
    }
}

// MARK: - OpenSourceAcknowledgmentsView
struct OpenSourceAcknowledgmentsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Notiee 感谢开源社区的力量，正是这些优秀的项目让我们的应用变得更好！")
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding()
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(12)
                
                VStack(alignment: .leading, spacing: 16) {
                    openSourceItem(name: "SwiftUI", url: "https://developer.apple.com/xcode/swiftui/", description: "Notiee 全面采用了 SwiftUI 构建现代化、响应式的用户界面，感谢苹果提供的强大底层框架。")
                    openSourceItem(name: "Swift Charts", url: "https://developer.apple.com/documentation/charts", description: "Notiee 的数据回顾仪表盘由 Swift Charts 提供图表渲染，直观展示您的 Token 消耗。")
                    openSourceItem(name: "swift-markdown-ui", url: "https://github.com/gonzalezreal/swift-markdown-ui", description: "Notiee 使用该库在详情页提供了优雅的 Markdown 渲染支持。")
                    openSourceItem(name: "ZIPFoundation", url: "https://github.com/weichsel/ZIPFoundation", description: "Notiee 使用该库提供了可靠的压缩和解压能力，用于处理 .tmn 文件的导入与导出。")
                    openSourceItem(name: "OnboardingKit", url: "https://github.com/danielsaidi/OnboardingKit", description: "Notiee 使用该库构建了精美的欢迎与首次引导页面。")
                    openSourceItem(name: "WhatsNewKit", url: "https://github.com/SvenTiigi/WhatsNewKit", description: "Notiee 使用该库来展示更新日志和新版本特性。")
                    openSourceItem(name: "Vision Framework", url: "https://developer.apple.com/documentation/vision", description: "原生提供了强大的 OCR 视觉框架，为 Notiee 本地初步的文字提取提供了技术支持。")
                }
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("开源声明")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func openSourceItem(name: String, url: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Link(name, destination: URL(string: url)!)
                .font(.headline)
                .foregroundColor(.blue)
            
            Text(description)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Divider()
        }
    }
}
