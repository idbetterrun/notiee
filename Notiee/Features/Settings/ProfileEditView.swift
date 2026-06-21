import SwiftUI
import PhotosUI

struct ProfileEditView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var account = AccountStore.live

    @State private var name: String = ""
    @State private var pickerItem: PhotosPickerItem?

    private var methodText: String {
        switch account.profile?.loginMethod {
        case .local: return String(localized: "本地")
        case .tomago: return "TomaGo"
        case nil: return ""
        }
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        avatarView
                            .frame(width: 88, height: 88)
                            .clipShape(Circle())
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "pencil.circle.fill")
                                    .foregroundStyle(.white, NotieeColors.primary)
                                    .font(.system(size: 22))
                            }
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            Section("用户名") {
                TextField("用户名", text: $name)
                    .onSubmit { commitName() }
            }

            Section {
                Text("当前通过 \(methodText) 方式登录")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Button(role: .destructive) {
                    account.logout()
                    dismiss()
                } label: {
                    Text("退出登录").frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("编辑个人信息")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { name = account.profile?.displayName ?? "" }
        .onDisappear { commitName() }
        .onChange(of: pickerItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    account.setAvatar(img)
                }
            }
        }
    }

    @ViewBuilder private var avatarView: some View {
        if let img = account.avatarImage {
            Image(uiImage: img).resizable().scaledToFill()
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable().scaledToFit()
                .foregroundStyle(.secondary)
        }
    }

    private func commitName() {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty, t != account.profile?.displayName {
            account.updateName(t)
        }
    }
}
