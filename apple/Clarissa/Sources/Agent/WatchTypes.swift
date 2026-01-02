import Foundation

// MARK: - Watch Communication Types
// These types are used for testing and can be shared with the Watch app
// The actual WatchConnectivity code is in WatchMessage.swift (excluded from SPM)

/// Request to process a user query (for testing)
public struct WatchQueryRequest: Codable, Sendable, Equatable {
    public let id: UUID
    public let text: String
    public let timestamp: Date
    
    public init(text: String) {
        self.id = UUID()
        self.text = text
        self.timestamp = Date()
    }
    
    public init(id: UUID, text: String, timestamp: Date) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
    }
}

/// Response containing the AI result (for testing)
public struct WatchQueryResponse: Codable, Sendable, Equatable {
    public let requestId: UUID
    public let text: String
    public let timestamp: Date
    
    public init(requestId: UUID, text: String) {
        self.requestId = requestId
        self.text = text
        self.timestamp = Date()
    }
    
    public init(requestId: UUID, text: String, timestamp: Date) {
        self.requestId = requestId
        self.text = text
        self.timestamp = timestamp
    }
}

/// Status updates during query processing (for testing)
public struct WatchProcessingStatus: Codable, Sendable, Equatable {
    public let requestId: UUID
    public let status: Status
    
    public enum Status: String, Codable, Sendable {
        case received
        case thinking
        case usingTool
        case processing
        case completed
    }
    
    public init(requestId: UUID, status: Status) {
        self.requestId = requestId
        self.status = status
    }
}

/// Error information (for testing)
public struct WatchErrorInfo: Codable, Sendable, Equatable {
    public let requestId: UUID?
    public let message: String
    public let isRecoverable: Bool
    
    public init(requestId: UUID? = nil, message: String, isRecoverable: Bool = true) {
        self.requestId = requestId
        self.message = message
        self.isRecoverable = isRecoverable
    }
}

