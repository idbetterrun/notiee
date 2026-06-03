import SwiftUI
import Charts


// MARK: - MeView
struct MeView: View {
    let settingsStore: AppSettingsPersisting
    @ObservedObject var store: NotieeStore

    var body: some View {
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

