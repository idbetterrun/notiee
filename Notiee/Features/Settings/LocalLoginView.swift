import SwiftUI
import PhotosUI

struct LocalLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var account = AccountStore.live

    @State private var name: String = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var pickedImage: UIImage?

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Form {
            Section("头像（可选）") {
                HStack {
                    Spacer()
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Group {
                            if let img = pickedImage {
                                Image(uiImage: img).resizable().scaledToFill()
                            } else {
                                Image(systemName: "person.crop.circle.fill")
                                    .resizable().scaledToFit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 88, height: 88)
                        .clipShape(Circle())
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            Section("用户名") {
                TextField("输入用户名（中英皆可）", text: $name)
            }
        }
        .navigationTitle("本地登录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") {
                    account.localLogin(name: trimmedName)
                    if let img = pickedImage { account.setAvatar(img) }
                    dismiss()
                }
                .disabled(trimmedName.isEmpty)
            }
        }
        .onChange(of: pickerItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    pickedImage = img
                }
            }
        }
    }
}
