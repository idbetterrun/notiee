import CoreGraphics
import Foundation

enum NewUIPreviewRecordSource: String, CaseIterable, Identifiable, Hashable {
    case photo
    case audio
    case text
    case notti

    var id: String { rawValue }

    var title: String {
        switch self {
        case .photo: return String(localized: "照片")
        case .audio: return String(localized: "录音")
        case .text: return String(localized: "文字")
        case .notti: return String(localized: "来自 Notti")
        }
    }

    var symbolName: String {
        switch self {
        case .photo: return "photo"
        case .audio: return "waveform"
        case .text: return "doc.text"
        case .notti: return "sparkles"
        }
    }
}

struct NewUIPreviewMedia: Identifiable, Equatable {
    let id: UUID
    let imageName: String
    let pixelSize: CGSize

    var aspectRatio: CGFloat {
        guard pixelSize.height > 0 else { return 1 }
        return pixelSize.width / pixelSize.height
    }
}

enum NewUIPreviewRecordRelationReason: String, Equatable, Hashable {
    case sameEvent
    case sameFolder
    case similarTopic

    var title: String {
        switch self {
        case .sameEvent: return String(localized: "同一日程")
        case .sameFolder: return String(localized: "同一文件夹")
        case .similarTopic: return String(localized: "相似主题")
        }
    }

    var symbolName: String {
        switch self {
        case .sameEvent: return "calendar"
        case .sameFolder: return "folder"
        case .similarTopic: return "sparkles"
        }
    }
}

struct NewUIPreviewRecordRelation: Identifiable, Equatable, Hashable {
    let recordID: UUID
    let reason: NewUIPreviewRecordRelationReason

    var id: UUID { recordID }
}

struct NewUIPreviewResolvedRecordRelation: Identifiable, Equatable {
    let fixture: NewUIPreviewRecordFixture
    let reason: NewUIPreviewRecordRelationReason

    var id: UUID { fixture.id }
}

struct NewUIPreviewRecordFixture: Identifiable, Equatable {
    var record: NoteRecord
    let previewSource: NewUIPreviewRecordSource
    let media: [NewUIPreviewMedia]
    let eventName: String?
    let folderName: String?
    var todos: [String]
    let relations: [NewUIPreviewRecordRelation]

    var id: UUID { record.id }

    /// Records cards intentionally expose summary only. Detail and OCR are detail-view content.
    var cardSummary: String { record.summary }
}

enum NewUIPreviewFixtures {
    static let referenceDate = Date(timeIntervalSince1970: 1_785_888_000)

    static let records: [NewUIPreviewRecordFixture] = [
        fixture(
            id: "10000000-0000-0000-0000-000000000001",
            minutesAgo: 18,
            mediaCount: 1,
            title: "产品周会：Q3 路线图",
            ocrText: "Whiteboard notes: launch, onboarding, retention.",
            summary: "确认了发布节奏、首次体验和留存验证三项重点。",
            detailedContent: "## 决策\n\n先完成发布节奏，再验证首次体验与留存指标。",
            keyPoints: ["发布节奏优先", "用数据验证首次体验"],
            definitions: [KeyDefinition(term: "留存验证", explanation: "观察用户是否持续回到产品。")],
            isFavorite: true,
            eventName: "产品周会",
            folderName: "工作",
            todos: ["整理路线图", "发送会议纪要"],
            relations: [
                ("10000000-0000-0000-0000-000000000011", .sameEvent),
                ("10000000-0000-0000-0000-000000000004", .sameFolder),
                ("10000000-0000-0000-0000-000000000002", .similarTopic)
            ]
        ),
        fixture(
            id: "10000000-0000-0000-0000-000000000002",
            minutesAgo: 46,
            daysAgo: 1,
            mediaCount: 0,
            title: "咖啡店里的界面灵感",
            summary: "",
            detailedContent: "用更轻的事实行承接大标题，让首屏先回答此刻最重要的事。",
            source: .text,
            folderName: "灵感",
            todos: ["画一版无框 Hero 草图"],
            relations: [
                ("10000000-0000-0000-0000-000000000001", .similarTopic),
                ("10000000-0000-0000-0000-000000000011", .similarTopic)
            ]
        ),
        fixture(
            id: "10000000-0000-0000-0000-000000000009",
            minutesAgo: 62,
            mediaCount: 1,
            mediaStartIndex: 3,
            title: "窗边的绿植",
            summary: "一张竖图记录了午后光线落在叶片和陶盆上的层次。",
            detailedContent: "单张竖图在概览中限制高度，在详情中保留完整比例。"
        ),
        fixture(
            id: "10000000-0000-0000-0000-000000000003",
            minutesAgo: 75,
            daysAgo: 2,
            mediaCount: 2,
            title: "街角光影",
            summary: "两张照片记录了午后建筑立面与树影。",
            detailedContent: "保留横向照片和竖向照片的真实比例。",
            folderName: "生活",
            relations: [
                ("10000000-0000-0000-0000-000000000009", .similarTopic),
                ("10000000-0000-0000-0000-000000000007", .sameFolder)
            ]
        ),
        fixture(
            id: "10000000-0000-0000-0000-000000000004",
            minutesAgo: 103,
            mediaCount: 3,
            title: "正在整理的白板",
            summary: "这段摘要在处理中保持稳定占位。",
            detailedContent: "尚未完成。",
            processingState: .processing,
            eventName: "设计评审",
            folderName: "工作",
            relations: [
                ("10000000-0000-0000-0000-000000000001", .sameFolder),
                ("10000000-0000-0000-0000-000000000011", .sameFolder)
            ]
        ),
        fixture(
            id: "10000000-0000-0000-0000-000000000005",
            minutesAgo: 132,
            mediaCount: 4,
            title: "待处理的读书页",
            summary: "图片已保存，正在等待整理。",
            processingState: .pending,
            folderName: "阅读"
        ),
        fixture(
            id: "10000000-0000-0000-0000-000000000006",
            minutesAgo: 180,
            mediaCount: 5,
            title: "展览动线记录",
            summary: "五张照片依次记录入口、展墙、互动区、休息区和出口。",
            detailedContent: "处理失败时仍允许进入详情查看已有素材。",
            processingState: .failed,
            isDeleted: true,
            folderName: "生活"
        ),
        fixture(
            id: "10000000-0000-0000-0000-000000000007",
            minutesAgo: 245,
            mediaCount: 6,
            title: "周末做饭步骤",
            ocrText: "番茄、罗勒、意面、橄榄油",
            summary: "六张照片保留从备料到装盘的完整过程。",
            detailedContent: "## 步骤\n\n1. 备料\n2. 熬酱\n3. 煮面\n4. 装盘",
            isFavorite: true,
            folderName: "生活",
            todos: ["补充食材用量"],
            relations: [
                ("10000000-0000-0000-0000-000000000003", .sameFolder),
                ("10000000-0000-0000-0000-000000000009", .similarTopic)
            ]
        ),
        fixture(
            id: "10000000-0000-0000-0000-000000000008",
            minutesAgo: 310,
            mediaCount: 2,
            title: "private roadmap sentinel",
            ocrText: "secret ocr sentinel",
            summary: "confidential summary sentinel",
            detailedContent: "sensitive detail sentinel",
            isEncrypted: true,
            eventName: "私人日程",
            folderName: "保险箱",
            todos: ["private todo sentinel"]
        ),
        fixture(
            id: "10000000-0000-0000-0000-000000000010",
            minutesAgo: 360,
            mediaCount: 0,
            title: "散步时的语音备忘",
            ocrText: "重新整理首页层级，让最重要的信息先出现。",
            summary: "一段关于首页信息层级和留白的语音想法。",
            detailedContent: "先确认页面的主任务，再决定每个模块应该占据多少空间。",
            source: .text,
            previewSource: .audio,
            eventName: "散步",
            todos: ["整理成界面草图"],
            relations: [
                ("10000000-0000-0000-0000-000000000002", .similarTopic),
                ("10000000-0000-0000-0000-000000000011", .similarTopic)
            ]
        ),
        fixture(
            id: "10000000-0000-0000-0000-000000000011",
            minutesAgo: 420,
            mediaCount: 0,
            title: "Notti 整理的发布复盘",
            summary: "Notti 汇总了发布过程中的决策、反馈和后续问题。",
            detailedContent: "## 复盘\n\n保留有效决策，同时继续验证首次体验。",
            source: .notti,
            previewSource: .notti,
            eventName: "产品周会",
            folderName: "工作",
            relations: [
                ("10000000-0000-0000-0000-000000000001", .sameEvent),
                ("10000000-0000-0000-0000-000000000004", .sameFolder),
                ("10000000-0000-0000-0000-000000000010", .similarTopic)
            ]
        )
    ]

    static func records(matching query: String, in fixtures: [NewUIPreviewRecordFixture] = records) -> [NewUIPreviewRecordFixture] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return fixtures }
        return fixtures.filter { fixture in
            guard !fixture.record.isEncrypted else { return false }
            return fixture.record.title.localizedCaseInsensitiveContains(normalized)
                || fixture.record.summary.localizedCaseInsensitiveContains(normalized)
        }
    }

    private static func fixture(
        id: String,
        minutesAgo: TimeInterval,
        daysAgo: Int = 0,
        mediaCount: Int,
        mediaStartIndex: Int = 0,
        title: String,
        ocrText: String = "",
        summary: String,
        detailedContent: String = "",
        processingState: AIProcessingState = .completed,
        keyPoints: [String] = [],
        definitions: [KeyDefinition] = [],
        source: RecordSource = .photo,
        previewSource: NewUIPreviewRecordSource? = nil,
        isEncrypted: Bool = false,
        isFavorite: Bool = false,
        isDeleted: Bool = false,
        eventName: String? = nil,
        folderName: String? = nil,
        todos: [String] = [],
        relations: [(String, NewUIPreviewRecordRelationReason)] = []
    ) -> NewUIPreviewRecordFixture {
        let media = (0..<mediaCount).map { index in
            mediaFixture(recordID: id, index: mediaStartIndex + index)
        }
        let record = NoteRecord(
            id: UUID(uuidString: id)!,
            capturedAt: referenceDate.addingTimeInterval(-minutesAgo * 60 - TimeInterval(daysAgo * 86_400)),
            localImagePaths: media.map(\.imageName),
            title: title,
            ocrText: ocrText,
            summary: summary,
            detailedContent: detailedContent,
            processingState: processingState,
            keyPoints: keyPoints,
            definitions: definitions,
            isFavorite: isFavorite,
            isDeleted: isDeleted,
            source: source,
            isEncrypted: isEncrypted
        )
        return NewUIPreviewRecordFixture(
            record: record,
            previewSource: previewSource ?? defaultPreviewSource(for: source),
            media: media,
            eventName: eventName,
            folderName: folderName,
            todos: todos,
            relations: relations.compactMap { rawID, reason in
                guard let recordID = UUID(uuidString: rawID) else { return nil }
                return NewUIPreviewRecordRelation(recordID: recordID, reason: reason)
            }
        )
    }

    private static func defaultPreviewSource(for source: RecordSource) -> NewUIPreviewRecordSource {
        switch source {
        case .photo: return .photo
        case .notti: return .notti
        case .text: return .text
        }
    }

    private static func mediaFixture(recordID: String, index: Int) -> NewUIPreviewMedia {
        let recordNumber = Int(recordID.suffix(2)) ?? 0
        let mediaNumber = recordNumber * 10 + index + 1
        let id = String(format: "20000000-0000-0000-0000-%012d", mediaNumber)
        let sizes = [
            CGSize(width: 1_200, height: 900),
            CGSize(width: 1_200, height: 900),
            CGSize(width: 1_200, height: 900),
            CGSize(width: 900, height: 1_200),
            CGSize(width: 1_200, height: 900),
            CGSize(width: 1_200, height: 900)
        ]
        return NewUIPreviewMedia(
            id: UUID(uuidString: id)!,
            imageName: String(format: "NewUIPreviewPhoto%02d", index % 6 + 1),
            pixelSize: sizes[index % sizes.count]
        )
    }
}
