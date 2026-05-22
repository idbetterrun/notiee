import Foundation
import ActivityKit
import SwiftUI

@MainActor
class LiveActivityManager: ObservableObject {
    static let shared = LiveActivityManager()
    
    private var currentActivity: Activity<ScheduleActivityAttributes>?
    
    private init() {
        // Find existing activity if app was restarted
        currentActivity = Activity<ScheduleActivityAttributes>.activities.first
    }
    
    func startActivity(for event: ScheduledEvent) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        
        // End existing activity if it's for a different event
        if let current = currentActivity {
            if current.attributes.eventID != event.id.uuidString {
                endActivity()
            } else {
                // If it's the same event, just update it
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
    }
    
    func endActivity() {
        guard let activity = currentActivity else { return }
        
        // Final state
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
}
