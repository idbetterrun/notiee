import Foundation
import SwiftUI

enum ScenePreset: String, CaseIterable, Codable, Identifiable, Sendable {
    case professional
    case college
    case highSchool
    case creator

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .professional: return "高效职场人"
        case .college: return "大学生 / 研究生"
        case .highSchool: return "中学生"
        case .creator: return "创作者 / 研究者"
        }
    }

    var iconName: String {
        switch self {
        case .professional: return "briefcase.fill"
        case .college: return "building.columns.fill"
        case .highSchool: return "backpack.fill"
        case .creator: return "paintbrush.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .professional: return .blue
        case .college: return .indigo
        case .highSchool: return .orange
        case .creator: return .purple
        }
    }

    var description: String {
        switch self {
        case .professional:
            return "侧重会议记录、任务提取，AI 帮你抓住每一个 action item。"
        case .college:
            return "课堂笔记整理、知识点提炼、LaTeX 公式识别，课程日历优先。"
        case .highSchool:
            return "板书 OCR 强化、作业提取、基础概念梳理，课程日历优先。"
        case .creator:
            return "全面视觉理解、深度关联、关键概念提取，适合研究与创作。"
        }
    }

    var enableKeyPoints: Bool {
        switch self {
        case .professional: return false
        case .college: return true
        case .highSchool: return true
        case .creator: return true
        }
    }

    var enableDefinitions: Bool {
        switch self {
        case .professional: return false
        case .college: return true
        case .highSchool: return true
        case .creator: return true
        }
    }

    var enableLaTeX: Bool {
        switch self {
        case .professional: return false
        case .college: return true
        case .highSchool: return true
        case .creator: return true
        }
    }

    var enableTodos: Bool {
        switch self {
        case .professional: return true
        case .college: return true
        case .highSchool: return true
        case .creator: return false
        }
    }

    var enableCourseMode: Bool {
        switch self {
        case .professional: return false
        case .college: return true
        case .highSchool: return true
        case .creator: return false
        }
    }

    var visionStrategy: VisionStrategy {
        switch self {
        case .professional: return .standard
        case .college: return .detailed
        case .highSchool: return .detailed
        case .creator: return .fullVision
        }
    }

    enum VisionStrategy: String, Codable, Sendable {
        case standard
        case detailed
        case fullVision
    }

    static var `default`: ScenePreset { .professional }

    static func load() -> ScenePreset {
        guard let rawValue = UserDefaults.standard.string(forKey: "notiee.scenePreset"),
              let preset = ScenePreset(rawValue: rawValue) else {
            return .default
        }
        return preset
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: "notiee.scenePreset")
    }
}
