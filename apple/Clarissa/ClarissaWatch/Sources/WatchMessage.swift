import Foundation

/// Messages exchanged between iPhone and Apple Watch
/// These are Codable for easy serialization via WatchConnectivity
enum WatchMessage: Codable, Sendable {
    /// Request from Watch to process a voice query
    case query(QueryRequest)
    
    /// Response from iPhone with the AI result
    case response(QueryResponse)
    
    /// Status update during processing
    case status(ProcessingStatus)
    
    /// Error occurred during processing
    case error(ErrorInfo)
    
    /// Ping to check connectivity
    case ping
    
    /// Pong response to ping
    case pong
}

// MARK: - Request Types

/// Request to process a user query
struct QueryRequest: Codable, Sendable {
    let id: UUID
    let text: String
    let timestamp: Date
    /// Optional template ID to apply before processing (nil = no template)
    let templateId: String?

    init(text: String, templateId: String? = nil) {
        self.id = UUID()
        self.text = text
        self.timestamp = Date()
        self.templateId = templateId
    }
}

// MARK: - Response Types

/// Response containing the AI result
struct QueryResponse: Codable, Sendable {
    let requestId: UUID
    let text: String
    let timestamp: Date
    
    init(requestId: UUID, text: String) {
        self.requestId = requestId
        self.text = text
        self.timestamp = Date()
    }
}

/// Status updates during query processing
struct ProcessingStatus: Codable, Sendable {
    let requestId: UUID
    let status: Status
    
    enum Status: String, Codable, Sendable {
        case received
        case thinking
        case usingTool
        case processing
        case completed
    }
}

/// Error information
struct ErrorInfo: Codable, Sendable {
    let requestId: UUID?
    let message: String
    let isRecoverable: Bool
    
    init(requestId: UUID? = nil, message: String, isRecoverable: Bool = true) {
        self.requestId = requestId
        self.message = message
        self.isRecoverable = isRecoverable
    }
}

// MARK: - Serialization

extension WatchMessage {
    /// Encode message to Data for WatchConnectivity
    func encode() throws -> Data {
        try JSONEncoder().encode(self)
    }
    
    /// Decode message from Data
    static func decode(from data: Data) throws -> WatchMessage {
        try JSONDecoder().decode(WatchMessage.self, from: data)
    }
    
    /// Convert to dictionary for sendMessage (interactive messaging)
    func toDictionary() throws -> [String: Any] {
        let data = try encode()
        return ["message": data]
    }
    
    /// Create from dictionary received via sendMessage
    static func from(dictionary: [String: Any]) throws -> WatchMessage {
        guard let data = dictionary["message"] as? Data else {
            throw WatchMessageError.invalidFormat
        }
        return try decode(from: data)
    }
}

enum WatchMessageError: LocalizedError {
    case invalidFormat
    case encodingFailed
    case decodingFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Invalid message format"
        case .encodingFailed:
            return "Failed to encode message"
        case .decodingFailed:
            return "Failed to decode message"
        }
    }
}

