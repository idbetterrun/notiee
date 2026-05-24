import ActivityKit
import WidgetKit
import SwiftUI

struct NotieeWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ScheduleActivityAttributes.self) { context in
            // Lock screen/banner UI
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: context.attributes.eventKind == "course" ? "book.fill" : (context.attributes.eventKind == "meeting" ? "person.2.fill" : "calendar"))
                        .foregroundColor(.blue)
                        .font(.title2)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.state.endTime > Date() ? "当前日程" : "日程已结束")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(context.state.eventTitle)
                        .font(.headline)
                        .lineLimit(1)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("距结束")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if context.state.endTime > Date() {
                        Text(timerInterval: Date()...context.state.endTime, countsDown: true)
                            .multilineTextAlignment(.trailing)
                            .font(.title2.monospacedDigit().weight(.bold))
                            .foregroundColor(.blue)
                            .frame(maxWidth: 90, alignment: .trailing)
                    } else {
                        Text("已结束")
                            .multilineTextAlignment(.trailing)
                            .font(.title2.monospacedDigit().weight(.bold))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: 90, alignment: .trailing)
                    }
                }
            }
            .padding()
            .activityBackgroundTint(Color(UIColor.systemBackground))
            .activitySystemActionForegroundColor(Color.black)
            
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack {
                        Image(systemName: context.attributes.eventKind == "course" ? "book.fill" : "calendar")
                            .foregroundColor(.blue)
                        Text("Notiee")
                            .font(.headline)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.endTime > Date() {
                        Text(timerInterval: Date()...context.state.endTime, countsDown: true)
                            .font(.headline.monospacedDigit())
                            .foregroundColor(.blue)
                    } else {
                        Text("已结束")
                            .font(.headline.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.eventTitle)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        Spacer()
                    }
                }
            } compactLeading: {
                Image(systemName: context.attributes.eventKind == "course" ? "book.fill" : "calendar")
                    .foregroundColor(.blue)
            } compactTrailing: {
                if context.state.endTime > Date() {
                    Text(timerInterval: Date()...context.state.endTime, countsDown: true)
                        .font(.caption.monospacedDigit())
                        .frame(maxWidth: 40)
                } else {
                    Text("结束")
                        .font(.caption.monospacedDigit())
                        .frame(maxWidth: 40)
                }
            } minimal: {
                Image(systemName: "calendar")
                    .foregroundColor(.blue)
            }
            .keylineTint(Color.blue)
        }
    }
}
