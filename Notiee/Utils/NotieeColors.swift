import SwiftUI

enum NotieeColors {
    static let primary = Color(red: 0.035, green: 0.773, blue: 0.463)
    static let secondary = Color(red: 0.204, green: 0.149, blue: 0.149)

    static func themed(_ defaultColor: Color) -> Color {
        UserDefaults.standard.string(forKey: UDK.accentColor) == "notiee" ? Self.primary : defaultColor
    }
}
