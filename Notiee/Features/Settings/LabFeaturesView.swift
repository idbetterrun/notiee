import SwiftUI

struct LabFeaturesView: View {
    @ObservedObject var store: NotieeStore
    @State private var showingDocumentPicker = false
    @State private var previewData: PreviewData?
    
    @AppStorage("labMarkdownRenderingEnabled") private var markdownRenderingEnabled = false
    @AppStorage("notiee.studentMode") private var studentModeEnabled = false
    
    var body: some View {
        Form {
            Section {
                VStack(spacing: 16) {
                    Image(systemName: "flask.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.purple)
                        .padding(.top, 8)
                    
                    Text("实验室功能")
                        .font(.headline)
                    
                    Text("这里是实验性质的功能，后续可能会删除，也可能会保留，请务必不要过多依赖。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            
            Section {
                Toggle(isOn: $markdownRenderingEnabled) {
                    Label("Markdown 渲染", systemImage: "m.square")
                }
            } footer: {
                Text("开启后，记录详情页若包含 Markdown 语法，将渲染为样式化排版。")
            }
            
            Section {
                Toggle(isOn: $studentModeEnabled) {
                    Label("学生模式", systemImage: "graduationcap.fill")
                }
            } footer: {
                Text("专为学生群体设计的功能模式。")
            }
            
            Section {
                Button {
                    showingDocumentPicker = true
                } label: {
                    HStack {
                        Label("导入 .tmn 文件", systemImage: "square.and.arrow.down")
                        Spacer()
                    }
                }
                .foregroundColor(.primary)
            } footer: {
                Text(".tmn 文件是 Notiee 及关联应用专属的结构化导出格式，支持包含图文等完整记录内容的无损备份与迁移。")
            }
        }
        .navigationTitle("实验室")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showingDocumentPicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                
                Task {
                    do {
                        let (record, todos) = try await TMNImportService.importTMN(url: url)
                        await MainActor.run {
                            self.previewData = PreviewData(record: record, todos: todos)
                        }
                    } catch {
                        print("Import failed: \(error.localizedDescription)")
                    }
                }
            case .failure(let error):
                print("Import failed: \(error.localizedDescription)")
            }
        }
        .sheet(item: $previewData) { data in
            TMNImportPreviewSheet(record: data.record, todos: data.todos, store: store)
        }
    }
}

struct PreviewData: Identifiable {
    let id = UUID()
    let record: NoteRecord
    let todos: [NoteTodo]
}
