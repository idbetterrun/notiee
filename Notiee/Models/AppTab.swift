import Foundation

enum AppTab: String, CaseIterable, Codable, Identifiable, Sendable {
    case today
    case capture
    case records
    case settings

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .today:
            "Today"
        case .capture:
            "拍记"
        case .records:
            "记录"
        case .settings:
            "我"
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
        case .settings:
            "person.crop.circle"
        }
    }

    static let launchCandidates: [AppTab] = [
        .today,
        .capture,
        .records
    ]
}
