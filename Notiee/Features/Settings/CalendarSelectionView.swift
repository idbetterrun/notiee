import SwiftUI
import Charts


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
                Text("取消勾选某个日历后，\(AppBranding.appName) 将不再读取该日历中的日程。系统日历（如节假日、生日等）默认显示在 Today 页面。")
            }
        }
        .navigationTitle("日程")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.loadCalendarSelection()
        }
    }
}

