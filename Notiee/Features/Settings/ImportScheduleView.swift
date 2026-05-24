import SwiftUI
import UniformTypeIdentifiers

struct ImportScheduleView: View {
    @ObservedObject var store: NotieeStore
    @Environment(\.dismiss) private var dismiss

    @State private var showFilePicker = false
    @State private var showImageSourceActionSheet = false
    @State private var showImagePicker = false
    @State private var showImageFilePicker = false
    @State private var imagePickerSourceType: UIImagePickerController.SourceType = .camera
    @State private var capturedImage: UIImage?
    @State private var importStatus: ImportStatus = .idle
    @State private var parsedEventsWrapper: ParsedEventsWrapper?

    var body: some View {
        List {
                Section {
                    Button {
                        showFilePicker = true
                    } label: {
                        HStack {
                            Image(systemName: "doc.text")
                                .foregroundStyle(.blue)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("导入 .ics 文件")
                                    .foregroundStyle(.primary)
                                Text("支持标准 iCalendar 格式的课程表文件")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    let aiConfigured = store.settingsStore.loadConfiguration(for: .text).isComplete
                    Button {
                        showImageSourceActionSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "photo.badge.plus")
                                .foregroundStyle(aiConfigured ? .blue : .gray)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("图片 AI 解析日程")
                                    .foregroundStyle(aiConfigured ? .primary : .secondary)
                                Text(aiConfigured ? "选择课程表截图，通过大模型自动解析" : "请先在设置中配置大模型")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(!aiConfigured)
                } header: {
                    Text("导入方式")
                } footer: {
                    Text("日程导入后将合并到今日视图中，可通过日历同步触发通知与实时活动。")
                }

                if let image = capturedImage {
                    Section("预览") {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .cornerRadius(8)
                    }
                }

                if case .parsing = importStatus {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("AI 正在解析课表...")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if case .success(let count) = importStatus {
                    Section {
                        Label("成功导入 \(count) 个日程", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                if case .failure(let message) = importStatus {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("导入日程")
            .navigationBarTitleDisplayMode(.inline)
            .background(
                EmptyView()
                    .fileImporter(
                        isPresented: $showFilePicker,
                        allowedContentTypes: [.calendarEvent, .text, UTType(filenameExtension: "ics") ?? .data, .data],
                        allowsMultipleSelection: false
                    ) { result in
                        importICSFile(result)
                    }
            )
            .background(
                EmptyView()
                    .fileImporter(
                        isPresented: $showImageFilePicker,
                        allowedContentTypes: [.image],
                        allowsMultipleSelection: false
                    ) { result in
                        switch result {
                        case .success(let urls):
                            guard let url = urls.first else { return }
                            if url.startAccessingSecurityScopedResource() {
                                defer { url.stopAccessingSecurityScopedResource() }
                                if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                                    self.capturedImage = image
                                }
                            } else {
                                if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                                    self.capturedImage = image
                                }
                            }
                        case .failure:
                            break
                        }
                    }
            )
            .sheet(isPresented: $showImagePicker) {
                ImageCaptureView(image: $capturedImage, sourceType: imagePickerSourceType)
            }
            .sheet(item: $parsedEventsWrapper) { wrapper in
                EventImportPreviewSheet(events: Binding(get: { wrapper.events }, set: { parsedEventsWrapper?.events = $0 }), store: store)
            }
            .confirmationDialog("选择图片来源", isPresented: $showImageSourceActionSheet, titleVisibility: .visible) {
                Button("拍照") {
                    imagePickerSourceType = .camera
                    showImagePicker = true
                }
                Button("从相册选择") {
                    imagePickerSourceType = .photoLibrary
                    showImagePicker = true
                }
                Button("从文件选择") {
                    showImageFilePicker = true
                }
                Button("取消", role: .cancel) {}
            }
            .onChange(of: capturedImage) { _, newImage in
                if let image = newImage {
                    parseImageWithAI(image)
                }
            }
    }

    private func importICSFile(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                parseICalendar(content)
            } catch {
                importStatus = .failure("文件读取失败：\(error.localizedDescription)")
            }
        case .failure(let error):
            importStatus = .failure("文件选择失败：\(error.localizedDescription)")
        }
    }

    private func parseICalendar(_ content: String) {
        var events: [ScheduledEvent] = []
        let lines = content.components(separatedBy: .newlines)

        var currentTitle: String?
        var currentStart: Date?
        var currentEnd: Date?

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        for line in lines {
            if line.hasPrefix("SUMMARY:") {
                currentTitle = String(line.dropFirst("SUMMARY:".count))
            } else if line.hasPrefix("DTSTART:") {
                let raw = String(line.dropFirst("DTSTART:".count))
                currentStart = dateFormatter.date(from: raw)
            } else if line.hasPrefix("DTEND:") {
                let raw = String(line.dropFirst("DTEND:".count))
                currentEnd = dateFormatter.date(from: raw)
            } else if line.hasPrefix("END:VEVENT") {
                if let title = currentTitle, let start = currentStart, let end = currentEnd {
                    let event = ScheduledEvent(title: title, startDate: start, endDate: end, kind: .course)
                    events.append(event)
                }
                currentTitle = nil
                currentStart = nil
                currentEnd = nil
            }
        }
        
        self.parsedEventsWrapper = ParsedEventsWrapper(events: events)
        importStatus = .idle
    }

    private func parseImageWithAI(_ image: UIImage) {
        importStatus = .parsing
        Task {
            do {
                guard let imageData = image.jpegData(compressionQuality: 0.6) else {
                    importStatus = .failure("图片处理失败")
                    return
                }

                let visionConfig = store.settingsStore.loadConfiguration(for: .vision)
                guard visionConfig.isComplete else {
                    importStatus = .failure("请先配置视觉模型")
                    return
                }

                let base64 = imageData.base64EncodedString()
                let prompt = """
                请识别图片中的课程表/日程表信息，提取出每一条日程，以 JSON 数组格式返回：
                [{"title": "课程名", "startDateTime": "yyyy-MM-dd HH:mm", "endDateTime": "yyyy-MM-dd HH:mm"}]
                如果识别不到内容，返回空数组 []。
                """

                let response: String
                if visionConfig.activeProtocol == .openai {
                    response = try await OpenAICaller.callVision(
                        endpoint: visionConfig.activeEndpoint,
                        model: visionConfig.modelName,
                        apiKey: visionConfig.apiKey,
                        base64Image: base64,
                        prompt: prompt
                    ).0
                } else {
                    response = try await AnthropicCaller.callVision(
                        endpoint: visionConfig.activeEndpoint,
                        model: visionConfig.modelName,
                        apiKey: visionConfig.apiKey,
                        base64Image: base64,
                        prompt: prompt
                    ).0
                }

                let cleaned = response
                    .replacingOccurrences(of: "```json", with: "")
                    .replacingOccurrences(of: "```", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                guard let data = cleaned.data(using: .utf8),
                      let items = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else {
                    importStatus = .failure("AI 返回结果解析失败")
                    return
                }

                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"

                var events: [ScheduledEvent] = []
                for item in items {
                    guard let title = item["title"],
                          let startStr = item["startDateTime"],
                          let endStr = item["endDateTime"],
                          let start = dateFormatter.date(from: startStr),
                          let end = dateFormatter.date(from: endStr) else { continue }
                    let event = ScheduledEvent(title: title, startDate: start, endDate: end, kind: .course)
                    events.append(event)
                }
                
                await MainActor.run {
                    self.parsedEventsWrapper = ParsedEventsWrapper(events: events)
                    self.importStatus = .idle
                }
            } catch {
                importStatus = .failure("解析失败：\(error.localizedDescription)")
            }
        }
    }
}

enum ImportStatus: Equatable {
    case idle
    case parsing
    case success(Int)
    case failure(String)
}

struct ParsedEventsWrapper: Identifiable {
    let id = UUID()
    var events: [ScheduledEvent]
}

private struct ImageCaptureView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    var sourceType: UIImagePickerController.SourceType
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImageCaptureView

        init(parent: ImageCaptureView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
