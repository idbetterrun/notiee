import SwiftUI
import Charts


// MARK: - MeView
struct MeView: View {
    let settingsStore: AppSettingsPersisting
    @ObservedObject var store: NotieeStore
    @ObservedObject private var account = AccountStore.live

    @ViewBuilder private var avatarView: some View {
        if let img = account.avatarImage {
            Image(uiImage: img).resizable().scaledToFill()
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable().scaledToFit()
                .foregroundColor(.accentColor)
        }
    }

    var body: some View {
        List {
            Section {
                if let profile = account.profile {
                    NavigationLink {
                        ProfileEditView()
                    } label: {
                        HStack(spacing: 16) {
                            avatarView
                                .frame(width: 50, height: 50)
                                .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text(AccountStore.greeting())
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text(profile.displayName)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text("编辑个人信息")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                } else {
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
            }
            
            Section {
                NavigationLink {
                    AllSchedulesView(store: store)
                } label: {
                    Label("全部日程", systemImage: "calendar")
                        .foregroundColor(NotieeColors.themed(.orange))
                }

                NavigationLink {
                    AllTodosView(store: store)
                } label: {
                    Label("所有待办", systemImage: "checklist")
                        .foregroundColor(NotieeColors.themed(.blue))
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
        .toolbar(.hidden, for: .tabBar)
    }
}

