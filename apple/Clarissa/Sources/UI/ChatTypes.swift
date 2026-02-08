import Foundation

/// Status of a tool execution
enum ToolStatus {
    case running
    case completed
    case failed
}

/// Current thinking/processing status for the typing indicator
enum ThinkingStatus: Equatable {
    case idle
    case thinking
    case usingTool(String)
    case processing

    /// Display text for the status
    var displayText: String {
        switch self {
        case .idle:
            return ""
        case .thinking:
            return "Thinking"
        case .usingTool(let toolName):
            return toolName
        case .processing:
            return "Processing"
        }
    }

    /// Whether the status is active (should show indicator)
    var isActive: Bool {
        self != .idle
    }
}

/// A message in the chat UI
struct ChatMessage: Identifiable {
    let id = UUID()
    var role: MessageRole
    var content: String
    var toolName: String?
    var toolStatus: ToolStatus?
    var toolResult: String?  // JSON result from tool execution
    var imageData: Data?  // Optional attached image preview
    var proactiveLabels: [String]?  // Proactive context sources used (e.g., ["weather", "calendar"])
    var isPinned: Bool = false  // Whether the user has pinned this message
    let timestamp = Date()

    /// Export message as markdown
    func toMarkdown() -> String {
        switch role {
        case .user:
            // Only add image note if not already in content and we have image data
            let hasImageNote = content.contains("[with image]")
            let imageNote = (imageData != nil && !hasImageNote) ? " [with image]" : ""
            return "**You:** \(content)\(imageNote)"
        case .assistant:
            return "**Clarissa:** \(content)"
        case .system:
            return "_System: \(content)_"
        case .tool:
            let status = toolStatus == .completed ? "completed" : (toolStatus == .failed ? "failed" : "running")
            return "> Tool: \(toolName ?? "unknown") (\(status))"
        }
    }
}

/// A single step in the agent's inferred execution plan
struct PlanStep: Identifiable, Equatable {
    let id = UUID()
    let toolName: String
    let displayName: String
    var status: PlanStepStatus

    enum PlanStepStatus: Equatable {
        case pending
        case running
        case completed
        case failed
    }
}

/// Maps tool names to human-readable display names
enum ToolDisplayNames {
    static func format(_ name: String) -> String {
        switch name {
        case "weather":
            return "Fetching weather"
        case "location":
            return "Getting location"
        case "calculator":
            return "Calculating"
        case "web_fetch":
            return "Fetching web content"
        case "calendar":
            return "Checking calendar"
        case "contacts":
            return "Searching contacts"
        case "reminders":
            return "Managing reminders"
        case "remember":
            return "Saving to memory"
        default:
            // Convert snake_case to Title Case
            return name.split(separator: "_")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
    }
}
