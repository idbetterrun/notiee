import Foundation

/// 一轮普通问答要注入 prompt 的记录集合，锚点在前、语义在后。
/// `[记录1..N]` 与 `[来源N]` 均按 `records` 数组的位置编号（1-based）。
struct RecalledRecords: Sendable {
    let records: [NoteRecord]
    /// records[semanticStartIndex...] 是全文语义层；前面是标题+摘要的锚点层。
    let semanticStartIndex: Int

    static let empty = RecalledRecords(records: [], semanticStartIndex: 0)
}

@MainActor
struct SparkRecordRecall {
    let engine: SemanticSearching
    var anchorCount: Int = 15
    var semanticLimit: Int = 8
    var mergedCap: Int = 20

    init(engine: SemanticSearching, anchorCount: Int = 15, semanticLimit: Int = 8, mergedCap: Int = 20) {
        self.engine = engine
        self.anchorCount = anchorCount
        self.semanticLimit = semanticLimit
        self.mergedCap = mergedCap
    }

    /// 锚点原序在前；语义去掉已在锚点里的；整体截到 cap。
    static func merge(anchors: [NoteRecord], semantic: [NoteRecord], cap: Int) -> RecalledRecords {
        let anchorIDs = Set(anchors.map { $0.id })
        let extras = semantic.filter { !anchorIDs.contains($0.id) }
        let merged = Array((anchors + extras).prefix(cap))
        let boundary = min(anchors.count, merged.count)
        return RecalledRecords(records: merged, semanticStartIndex: boundary)
    }
}
