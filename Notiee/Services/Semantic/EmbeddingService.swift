import Foundation
import CryptoKit

/// 语义向量服务抽象。无法计算时抛错，由上层降级处理。
protocol EmbeddingService: Sendable {
    /// 模型标识，写入索引用于失效判断。
    var modelIdentifier: String { get }
    func embed(_ text: String) async throws -> [Float]
}

enum EmbeddingError: LocalizedError {
    case unavailable
    case cannotEmbed
    case notConfigured
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "语义向量引擎不可用"
        case .cannotEmbed: return "无法对文本计算向量"
        case .notConfigured: return "云端向量未配置"
        case .requestFailed(let m): return "向量请求失败：\(m)"
        }
    }
}

/// 把一条拍记拼成用于 embedding 的文本，并提供内容哈希。
enum RecordEmbeddingText {
    static let maxLength = 2000

    static func compose(_ record: NoteRecord) -> String {
        // 顺序：标题/摘要/正文（语义最密）在前，OCR 原文在后，
        // 超长截断时优先保留高信息密度内容。纳入正文让纯文本/Spark 记录也能联想。
        let joined = [record.title, record.summary, record.detailedContent, record.ocrText]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return String(joined.prefix(maxLength))
    }

    /// SHA256 十六进制，跨进程稳定（不可用 hashValue）。
    static func contentHash(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
