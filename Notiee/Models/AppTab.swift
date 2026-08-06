import Foundation
import SwiftUI

enum AppTab: CaseIterable, Codable, Identifiable, Sendable {
    case today
    case capture
    case records
    case notti

    /// `spark` remains the persisted identifier for backward/rollback safety.
    var rawValue: String {
        switch self {
        case .today: "today"
        case .capture: "capture"
        case .records: "records"
        case .notti: "spark"
        }
    }

    init?(rawValue: String) {
        switch rawValue {
        case "today": self = .today
        case "capture": self = .capture
        case "records": self = .records
        case "spark", "notti": self = .notti
        default: return nil
        }
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = Self(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Unknown app tab: \(raw)"
            )
        }
        self = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

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
        case .notti:
            return "Notti"
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
        case .notti:
            "sparkles"
        }
    }

    static let launchCandidates: [AppTab] = [
        .today,
        .capture,
        .records,
        .notti
    ]
}
