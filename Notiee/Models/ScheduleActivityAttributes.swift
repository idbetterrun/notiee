import Foundation
import ActivityKit

public struct ScheduleActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var eventTitle: String
        public var endTime: Date
        
        public init(eventTitle: String, endTime: Date) {
            self.eventTitle = eventTitle
            self.endTime = endTime
        }
    }

    public var eventID: String
    public var eventKind: String
    
    public init(eventID: String, eventKind: String) {
        self.eventID = eventID
        self.eventKind = eventKind
    }
}
