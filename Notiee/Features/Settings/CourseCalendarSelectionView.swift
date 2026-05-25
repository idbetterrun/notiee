import SwiftUI
import EventKit

struct CourseCalendarSelectionView: View {
    @State private var calendars: [EKCalendar] = []
    @State private var courseIDs: Set<String> = []

    var body: some View {
        Form {
            Section {
                VStack(spacing: 16) {
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.blue)
                        .padding(.top, 8)

                    Text("我的课程")
                        .font(.headline)

                    Text("将日历标记为课程后，其日程将在拍记页路径选择中置顶显示，方便快速选择。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section {
                if calendars.isEmpty {
                    Text("未找到可用的系统日历")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(calendars, id: \.calendarIdentifier) { calendar in
                        Button {
                            CalendarService.shared.toggleCourseCalendar(calendar.calendarIdentifier)
                            courseIDs = CalendarService.shared.courseCalendarIDs()
                        } label: {
                            HStack {
                                Circle()
                                    .fill(Color(cgColor: calendar.cgColor))
                                    .frame(width: 12, height: 12)
                                Text(calendar.title)
                                    .foregroundColor(.primary)
                                Spacer()
                                if courseIDs.contains(calendar.calendarIdentifier) {
                                    Text("📖")
                                }
                            }
                        }
                    }
                }
            } footer: {
                Text("标记后的日历会将其中所有日程视为课程。拍记时，课程相关日程会优先显示。")
            }
        }
        .navigationTitle("我的课程")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            calendars = CalendarService.shared.availableCalendars.filter { !CalendarService.shared.isHolidayCalendar($0) }
            courseIDs = CalendarService.shared.courseCalendarIDs()
        }
    }
}
