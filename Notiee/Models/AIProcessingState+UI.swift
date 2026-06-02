import SwiftUI

extension AIProcessingState {
    var displayName: String {
        switch self {
        case .pending: return "待处理"
        case .processing: return "处理中"
        case .completed: return "已完成"
        case .failed: return "处理失败"
        case .deadLetter: return "已达最大重试次数"
        }
    }

    var symbolName: String {
        switch self {
        case .pending: return "clock"
        case .processing: return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle"
        case .deadLetter: return "envelope.badge.person.crop"
        }
    }

    var tint: Color {
        switch self {
        case .pending: return .orange
        case .processing: return .blue
        case .completed: return .green
        case .failed: return .red
        case .deadLetter: return .red
        }
    }
}
