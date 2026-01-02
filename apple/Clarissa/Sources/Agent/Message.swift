import Foundation

/// Role of a message in the conversation
public enum MessageRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
}

/// A tool call requested by the assistant
public struct ToolCall: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let arguments: String

    public init(id: String = UUID().uuidString, name: String, arguments: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

/// A message in the conversation
public struct Message: Identifiable, Codable, Sendable {
    public let id: UUID
    public let role: MessageRole
    public var content: String
    public let toolCalls: [ToolCall]?
    public let toolCallId: String?
    public let toolName: String?
    public let imageData: Data?  // Optional attached image (thumbnail for display)
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        toolCalls: [ToolCall]? = nil,
        toolCallId: String? = nil,
        toolName: String? = nil,
        imageData: Data? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.imageData = imageData
        self.createdAt = createdAt
    }

    public static func system(_ content: String) -> Message {
        Message(role: .system, content: content)
    }

    public static func user(_ content: String, imageData: Data? = nil) -> Message {
        Message(role: .user, content: content, imageData: imageData)
    }

    public static func assistant(_ content: String, toolCalls: [ToolCall]? = nil) -> Message {
        Message(role: .assistant, content: content, toolCalls: toolCalls)
    }

    public static func tool(callId: String, name: String, content: String) -> Message {
        Message(role: .tool, content: content, toolCallId: callId, toolName: name)
    }
}

/// Represents a streaming chunk from the LLM
public struct StreamChunk: Sendable {
    public let content: String?
    public let toolCalls: [ToolCall]?
    public let isComplete: Bool
}

