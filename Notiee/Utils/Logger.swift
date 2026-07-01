import Foundation
import OSLog

enum Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.notiee.app"

    static let general = os.Logger(subsystem: subsystem, category: "general")
    static let ai = os.Logger(subsystem: subsystem, category: "ai")
    static let storage = os.Logger(subsystem: subsystem, category: "storage")
    static let calendar = os.Logger(subsystem: subsystem, category: "calendar")
    static let network = os.Logger(subsystem: subsystem, category: "network")
    static let camera = os.Logger(subsystem: subsystem, category: "camera")
    static let spark = os.Logger(subsystem: subsystem, category: "spark")

    static func logError(_ error: Error, category: os.Logger = general, file: String = #fileID, line: Int = #line) {
        category.error("[\(file):\(line)] \(error.localizedDescription, privacy: .public)")
    }

    static func logWarning(_ message: String, category: os.Logger = general) {
        category.warning("\(message, privacy: .public)")
    }

    static func logInfo(_ message: String, category: os.Logger = general) {
        category.info("\(message, privacy: .public)")
    }

    static func logDebug(_ message: String, category: os.Logger = general) {
        category.debug("\(message, privacy: .public)")
    }
}
