import Foundation

final class NoteSearchTool: AgentTool {
    let name = "note_search"
    let description = "在用户的所有拍记中搜索相关内容。支持关键词检索。返回匹配的记录列表及其摘要。"
    let permission: AgentToolPermission = .read

    let parametersSchema = AgentToolParametersSchema(
        properties: [
            "query": AgentToolProperty(type: "string", description: "搜索关键词或自然语言查询。越具体越好。", enumValues: nil, items: nil),
            "time_range": AgentToolProperty(type: "string", description: "时间范围限定", enumValues: ["today", "this_week", "this_month", "half_year", "one_year", "all"], items: nil),
            "limit": AgentToolProperty(type: "number", description: "最大返回条数，默认5条", enumValues: nil, items: nil)
        ],
        required: ["query"]
    )

    let recordManager: RecordManager

    init(recordManager: RecordManager) {
        self.recordManager = recordManager
    }

    func execute(parameters: [String: Any]) async throws -> AgentToolResult {
        guard let query = parameters["query"] as? String else {
            throw AgentToolError.missingParameter("query")
        }

        let limit = (parameters["limit"] as? Int) ?? 5
        let timeRangeStr = parameters["time_range"] as? String

        var records = recordManager.sortedRecords
        if let range = timeRangeStr {
            records = filterByTimeRange(records, range)
        }

        let queryLower = query.lowercased()
        let candidates = records.filter {
            $0.title.localizedCaseInsensitiveContains(queryLower)
                || $0.summary.localizedCaseInsensitiveContains(queryLower)
                || $0.ocrText.localizedCaseInsensitiveContains(queryLower)
        }

        let results = Array(candidates.prefix(limit))
        let recordsData = results.enumerated().map { i, record -> [String: Any] in
            return [
                "index": i + 1,
                "record_id": record.id.uuidString,
                "title": record.title,
                "captured_at": record.capturedAt.ISO8601Format(),
                "summary": String(record.summary.prefix(200)),
                "is_favorite": record.isFavorite
            ]
        }

        let message = results.isEmpty
            ? "未找到与「\(query)」相关的拍记。"
            : "找到 \(results.count) 条与「\(query)」相关的拍记：\n"
                + results.enumerated().map { "  [记录\($0+1)] \($1.title) (\($1.capturedAt.formatted(date: .abbreviated, time: .shortened)))" }.joined(separator: "\n")

        return AgentToolResult(success: true, message: message, data: ["records": recordsData], undoAction: nil)
    }

    private func filterByTimeRange(_ records: [NoteRecord], _ range: String) -> [NoteRecord] {
        let now = Date()
        let calendar = Calendar.current
        let start: Date?
        switch range {
        case "today": start = calendar.startOfDay(for: now)
        case "this_week": start = calendar.date(byAdding: .day, value: -7, to: now)
        case "this_month": start = calendar.date(byAdding: .month, value: -1, to: now)
        case "half_year": start = calendar.date(byAdding: .month, value: -6, to: now)
        case "one_year": start = calendar.date(byAdding: .year, value: -1, to: now)
        default: return records
        }
        guard let s = start else { return records }
        return records.filter { $0.capturedAt >= s }
    }
}

enum AgentToolError: Error {
    case missingParameter(String)
    case snapshotWriteFailed
}
