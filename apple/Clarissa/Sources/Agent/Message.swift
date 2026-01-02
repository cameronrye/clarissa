import Foundation

/// Role of a message in the conversation
enum MessageRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
}

/// A tool call requested by the assistant
struct ToolCall: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let arguments: String
    
    init(id: String = UUID().uuidString, name: String, arguments: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

/// A message in the conversation
struct Message: Identifiable, Codable, Sendable {
    let id: UUID
    let role: MessageRole
    var content: String
    let toolCalls: [ToolCall]?
    let toolCallId: String?
    let toolName: String?
    let imageData: Data?  // Optional attached image (thumbnail for display)
    let createdAt: Date

    init(
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

    static func system(_ content: String) -> Message {
        Message(role: .system, content: content)
    }

    static func user(_ content: String, imageData: Data? = nil) -> Message {
        Message(role: .user, content: content, imageData: imageData)
    }

    static func assistant(_ content: String, toolCalls: [ToolCall]? = nil) -> Message {
        Message(role: .assistant, content: content, toolCalls: toolCalls)
    }

    static func tool(callId: String, name: String, content: String) -> Message {
        Message(role: .tool, content: content, toolCallId: callId, toolName: name)
    }
}

/// Represents a streaming chunk from the LLM
struct StreamChunk: Sendable {
    let content: String?
    let toolCalls: [ToolCall]?
    let isComplete: Bool
}

