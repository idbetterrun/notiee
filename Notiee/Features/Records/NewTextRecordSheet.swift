import SwiftUI

struct NewTextRecordSheet: View {
    @ObservedObject var store: NotieeStore
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var bodyText: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("标题", text: $title, axis: .vertical)
                        .font(.system(size: 28, weight: .bold))
                        .textInputAutocapitalization(.sentences)

                    Divider()

                    TextField("正文", text: $bodyText, axis: .vertical)
                        .font(.body)
                        .frame(minHeight: 200, alignment: .topLeading)
                }
                .padding(20)
            }
            .navigationTitle("纯文字记录（beta）")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  && bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = NoteRecord(
            localImagePaths: [],
            // 纯文本由用户手敲，没有 AI 摘要——留空，正文即内容。
            title: trimmedTitle.isEmpty ? "无标题" : trimmedTitle,
            summary: "",
            detailedContent: bodyText,
            processingState: .completed,
            source: .text
        )
        store.addRecord(record)
        dismiss()
    }
}
