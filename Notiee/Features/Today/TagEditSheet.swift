import SwiftUI

struct TagEditSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var store: NotieeStore
    
    @State private var tagName: String = ""
    @State private var tagColor: Color = .blue
    
    var body: some View {
        NavigationStack {
            Form {
                Section("标签信息") {
                    TextField("标签名称", text: $tagName)
                    ColorPicker("标签颜色", selection: $tagColor, supportsOpacity: false)
                }
            }
            .navigationTitle("新建标签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let uiColor = UIColor(tagColor)
                        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
                        let hex = String(format: "#%02lX%02lX%02lX", lroundf(Float(r * 255)), lroundf(Float(g * 255)), lroundf(Float(b * 255)))
                        store.createTag(name: tagName.isEmpty ? "未命名标签" : tagName, colorHex: hex)
                        dismiss()
                    }
                }
            }
        }
    }
}
