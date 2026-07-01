import SwiftUI

struct SpecialDayEvent: Identifiable {
    enum EventType {
        case holiday
        case birthday
        case solarTerm
    }

    let id = UUID()
    let title: String
    let type: EventType

    var color: Color {
        switch type {
        case .holiday: return .red
        case .birthday: return .pink
        case .solarTerm: return .green
        }
    }
}
