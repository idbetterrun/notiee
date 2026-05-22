import SwiftUI

struct EventTag: Identifiable, Equatable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var colorHex: String
    let isSystem: Bool
    
    init(id: UUID = UUID(), name: String, colorHex: String, isSystem: Bool = false) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.isSystem = isSystem
    }
    
    var color: Color {
        Color(hex: colorHex) ?? .gray
    }
}

extension EventTag {
    static let personal = EventTag(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "个人", colorHex: "#007AFF", isSystem: true)
    static let work = EventTag(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "工作", colorHex: "#FF9500", isSystem: true)
    static let course = EventTag(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, name: "课程", colorHex: "#34C759", isSystem: true)
    static let temporary = EventTag(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!, name: "临时", colorHex: "#AF52DE", isSystem: true)
    
    static let systemTags: [EventTag] = [.personal, .work, .course, .temporary]
}

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        var r: CGFloat = 0.0
        var g: CGFloat = 0.0
        var b: CGFloat = 0.0
        var a: CGFloat = 1.0

        let length = hexSanitized.count

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        if length == 6 {
            r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
            g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
            b = CGFloat(rgb & 0x0000FF) / 255.0

        } else if length == 8 {
            r = CGFloat((rgb & 0xFF000000) >> 24) / 255.0
            g = CGFloat((rgb & 0x00FF0000) >> 16) / 255.0
            b = CGFloat((rgb & 0x0000FF00) >> 8) / 255.0
            a = CGFloat(rgb & 0x000000FF) / 255.0
        } else {
            return nil
        }

        self.init(red: r, green: g, blue: b, opacity: a)
    }
}
