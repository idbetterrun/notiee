import Foundation
import ActivityKit
import SwiftUI
import UserNotifications

@MainActor
class LiveActivityManager: ObservableObject {
    static let shared = LiveActivityManager()
    
    private var currentActivity: Activity<ScheduleActivityAttributes>?
    private static let endNotificationPrefix = "liveactivity-end-"
    
    private init() {
        currentActivity = Activity<ScheduleActivityAttributes>.activities.first
    }
    
    func startActivity(for event: ScheduledEvent) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        
        if let current = currentActivity {
            if current.attributes.eventID != event.id.uuidString {
                endActivity()
            } else {
                updateActivity(for: event)
                return
            }
        }
        
        let attributes = ScheduleActivityAttributes(
            eventID: event.id.uuidString,
            eventKind: event.kind.rawValue
        )
        
        let contentState = ScheduleActivityAttributes.ContentState(
            eventTitle: event.title,
            endTime: event.endDate
        )
        
        let content = ActivityContent(state: contentState, staleDate: event.endDate)
        
        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            scheduleAutoEnd(for: event)
        } catch {
            print("Failed to start Live Activity: \(error)")
        }
    }
    
    func updateActivity(for event: ScheduledEvent) {
        guard let activity = currentActivity else {
            startActivity(for: event)
            return
        }
        
        let contentState = ScheduleActivityAttributes.ContentState(
            eventTitle: event.title,
            endTime: event.endDate
        )
        
        let content = ActivityContent(state: contentState, staleDate: event.endDate)
        
        Task {
            await activity.update(content)
        }
        scheduleAutoEnd(for: event)
    }
    
    func endActivity() {
        guard let activity = currentActivity else { return }
        
        let finalState = ScheduleActivityAttributes.ContentState(
            eventTitle: "日程已结束",
            endTime: Date()
        )
        
        let finalContent = ActivityContent(state: finalState, staleDate: nil)
        
        Task {
            await activity.end(finalContent, dismissalPolicy: .default)
        }
        
        currentActivity = nil
    }
    
    private func scheduleAutoEnd(for event: ScheduledEvent) {
        let notificationID = "\(Self.endNotificationPrefix)\(event.id.uuidString)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
        
        let timeUntilEnd = event.endDate.timeIntervalSinceNow
        guard timeUntilEnd > 0 else {
            endActivity()
            return
        }
        
        let content = UNMutableNotificationContent()
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeUntilEnd, repeats: false)
        let request = UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to schedule Live Activity end notification: \(error)")
            }
        }
    }
    
    static func isEndNotification(_ identifier: String) -> Bool {
        return identifier.hasPrefix(endNotificationPrefix)
    }
}
