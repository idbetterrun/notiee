import SwiftUI
import PhotosUI

struct ProfileEditView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var account = AccountStore.live

    @State private var name: String = ""
    @State private var pickerItem: PhotosPickerItem?
    #if !NOTIEE_PLUS
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var deleteErrorMessage: String?
    #endif

    private var methodText: String {
        switch account.profile?.loginMethod {
        case .local: return String(localized: "本地")
        case .apple, .tomago: return "Apple"
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
                    #if !NOTIEE_PLUS
                    AuthService.shared.signOut()
                    #endif
                    account.logout()
                    dismiss()
                } label: {
                    Text("退出登录").frame(maxWidth: .infinity)
                }
            }

            #if !NOTIEE_PLUS
            // App Review 5.1.1(v): an app with account login must offer in-app
            // account deletion (removes backend data + revokes Apple token).
            Section {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    if isDeleting {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("删除账户").frame(maxWidth: .infinity)
                    }
                }
                .disabled(isDeleting)
            } footer: {
                Text("永久删除你的账户及云端数据，此操作不可撤销。")
            }
            #endif
        }
        .navigationTitle("编辑个人信息")
        .navigationBarTitleDisplayMode(.inline)
        #if !NOTIEE_PLUS
        .alert("删除账户", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { performAccountDeletion() }
        } message: {
            Text("确定要永久删除账户吗？账户及云端数据将无法恢复。")
        }
        .alert("删除失败", isPresented: Binding(get: { deleteErrorMessage != nil }, set: { if !$0 { deleteErrorMessage = nil } })) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? "")
        }
        #endif
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

    #if !NOTIEE_PLUS
    private func performAccountDeletion() {
        isDeleting = true
        Task { @MainActor in
            do {
                try await AuthService.shared.deleteAccount() // clears the local session on success
                account.logout()
                isDeleting = false
                dismiss()
            } catch {
                isDeleting = false
                deleteErrorMessage = String(localized: "删除账户失败，请稍后重试。")
            }
        }
    }
    #endif

    private func commitName() {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty, t != account.profile?.displayName {
            account.updateName(t)
        }
    }
}
