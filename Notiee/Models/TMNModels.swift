import Foundation

struct TMNManifest: Codable {
    let format: String
    let metadata: Metadata
    let files: [FileEntry]
    let content: ContentSpec
    
    struct Metadata: Codable {
        let app: String
        let appVersion: String
        let createdAt: String
        let documentId: String
        let encrypted: Bool
        
        enum CodingKeys: String, CodingKey {
            case app
            case appVersion = "app_version"
            case createdAt = "created_at"
            case documentId = "document_id"
            case encrypted
        }
    }
    
    struct FileEntry: Codable {
        let path: String
        let size: Int
        let mimeType: String
        
        enum CodingKeys: String, CodingKey {
            case path, size
            case mimeType = "mime_type"
        }
    }
    
    struct ContentSpec: Codable {
        let main: String
        let type: String
        let schemaVersion: String
        
        enum CodingKeys: String, CodingKey {
            case main, type
            case schemaVersion = "schema_version"
        }
    }
}

struct TMNContent: Codable {
    let id: String
    let type: String
    let title: String
    let description: String?
    let createdAt: String
    let updatedAt: String
    let tags: [String]?
    let encryption: Encryption
    let content: ContentData
    let appData: AppData?
    
    enum CodingKeys: String, CodingKey {
        case id, type, title, description
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case tags, encryption, content
        case appData = "app_data"
    }
    
    struct Encryption: Codable {
        let enabled: Bool
    }
    
    struct ContentData: Codable {
        let format: String
        let text: String
        let attachmentsRefs: [AttachmentRef]?
        
        enum CodingKeys: String, CodingKey {
            case format, text
            case attachmentsRefs = "attachments_refs"
        }
    }
    
    struct AttachmentRef: Codable {
        let id: String
        let path: String
        let type: String
        let label: String?
    }
    
    struct AppData: Codable {
        let notiee: NotieeAppData?
    }
    
    struct NotieeAppData: Codable {
        let event: EventData?
        let aiProcessing: AIProcessingData?
        let deviceName: String?
        
        enum CodingKeys: String, CodingKey {
            case event
            case aiProcessing = "ai_processing"
            case deviceName = "device_name"
        }
    }
    
    struct EventData: Codable {
        let id: String
        let title: String
        let type: String
    }
    
    struct AIProcessingData: Codable {
        let state: String
        let ocrText: String?
        let summary: String?
        let detailedContent: String?
        let todos: [TodoData]?
        let modelsUsed: [String]?
        let tokenUsage: Int?
        
        enum CodingKeys: String, CodingKey {
            case state
            case ocrText = "ocr_text"
            case summary
            case detailedContent = "detailed_content"
            case todos
            case modelsUsed = "models_used"
            case tokenUsage = "token_usage"
        }
    }
    
    struct TodoData: Codable {
        let id: String
        let content: String
        let isCompleted: Bool
        let createdAt: String
        
        enum CodingKeys: String, CodingKey {
            case id, content
            case isCompleted = "is_completed"
            case createdAt = "created_at"
        }
    }
}
