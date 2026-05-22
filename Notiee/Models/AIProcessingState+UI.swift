import SwiftUI

extension AIProcessingState {
    var displayName: String {
        switch self {
        case .pending: return "等待处理"
        case .processing: return "AI 处理中"
        case .completed: return "已生成摘要"
        case .failed: return "处理失败"
        }
    }

    var symbolName: String {
        switch self {
        case .pending: return "clock"
        case .processing: return "sparkles"
        case .completed: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        }
    }

    var tint: Color {
        switch self {
        case .pending: return .orange
        case .processing: return .blue
        case .completed: return .green
        case .failed: return .red
        }
    }
}
