import Foundation
import UserNotifications

@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    private init() {}
    
    func requestPermission() async -> Bool {
        do {
            let options: UNAuthorizationOptions = [.alert, .sound, .badge]
            return try await UNUserNotificationCenter.current().requestAuthorization(options: options)
        } catch {
            print("Failed to request notification permission: \(error)")
            return false
        }
    }
    
    func scheduleNotifications(for events: [ScheduledEvent], advanceTimeMinutes: Int) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests() // Reset all notifications
        
        guard UserDefaults.standard.bool(forKey: UDK.notificationEnabled) else { return }
        
        for event in events {
            guard event.startDate > Date() else { continue } // Only upcoming
            
            let triggerDate = event.startDate.addingTimeInterval(-Double(advanceTimeMinutes * 60))
            guard triggerDate > Date() else { continue }
            
            let content = UNMutableNotificationContent()
            content.title = "日程提醒"
            if advanceTimeMinutes == 0 {
                content.body = "您的日程「\(event.title)」马上开始！"
            } else {
                content.body = "您的日程「\(event.title)」将在 \(advanceTimeMinutes) 分钟后开始。"
            }
            content.sound = .default
            
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            
            let request = UNNotificationRequest(identifier: event.id.uuidString, content: content, trigger: trigger)
            
            center.add(request) { error in
                if let error = error {
                    print("Error scheduling notification: \(error)")
                }
            }
        }
    }
}

extension NotificationManager: ProcessingResultNotifying {
    func notify(recordID: UUID, outcome: AIProcessingState) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return true
        }

        let identifier = "notiee.ai-processing.\(recordID.uuidString)"
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = String(localized: outcome == .completed
            ? "截图已整理完成"
            : "截图已保存，但整理暂未完成")
        content.body = String(localized: outcome == .completed
            ? "已生成拍记摘要。"
            : "原图和拍记已保留，可稍后重试。")
        content.sound = .default

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

        return await withCheckedContinuation { continuation in
            center.add(request) { error in
                continuation.resume(returning: error == nil)
            }
        }
    }
}
