import Foundation
import SwiftUI

enum AppTab: String, CaseIterable, Codable, Identifiable, Sendable {
    case today
    case capture
    case records
    case spark

    var id: String {
        rawValue
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .today:
            return "Today"
        case .capture:
            return "Snap"
        case .records:
            return "Records"
        case .spark:
            return "Spark"
        }
    }

    var systemImage: String {
        switch self {
        case .today:
            "calendar"
        case .capture:
            "camera.viewfinder"
        case .records:
            "book.closed"
        case .spark:
            "sparkles"
        }
    }

    static let launchCandidates: [AppTab] = [
        .today,
        .capture,
        .records
    ]
}
