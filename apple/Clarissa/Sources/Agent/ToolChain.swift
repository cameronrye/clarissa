import Foundation

// MARK: - Tool Chain Model

/// A multi-step workflow that chains tool outputs into subsequent tool inputs.
/// Tool chains power scheduled check-ins, Shortcuts actions, and one-tap workflows.
public struct ToolChain: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var description: String
    public var icon: String  // SF Symbol name
    public var steps: [ToolChainStep]
    public let createdAt: Date

    /// Whether this is a built-in chain (not deletable)
    public var isBuiltIn: Bool { ToolChain.builtIn.contains(where: { $0.id == id }) }
}

/// A single step in a tool chain
public struct ToolChainStep: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var toolName: String
    /// JSON argument template with optional `$N.path` references to previous step outputs.
    /// Example: `{"location": "$0.events[0].location"}` pipes step 0's event location into this step.
    public var argumentTemplate: String
    /// Human-readable label shown in chain preview (e.g., "Get today's weather")
    public var label: String
    /// Whether this step can be skipped by the user during preview
    public var isOptional: Bool

    public init(
        id: UUID = UUID(),
        toolName: String,
        argumentTemplate: String = "{}",
        label: String,
        isOptional: Bool = false
    ) {
        self.id = id
        self.toolName = toolName
        self.argumentTemplate = argumentTemplate
        self.label = label
        self.isOptional = isOptional
    }
}

// MARK: - Execution State

/// Status of a tool chain step during execution
public enum ChainStepStatus: Sendable {
    case pending
    case running
    case completed(result: String)
    case skipped
    case failed(error: String)

    public var isTerminal: Bool {
        switch self {
        case .completed, .skipped, .failed: return true
        case .pending, .running: return false
        }
    }
}

/// Result of executing a complete tool chain
public struct ToolChainResult: Sendable {
    public let chainId: String
    public let stepResults: [StepResult]
    public let duration: TimeInterval
    /// True when the chain stopped early because a required step failed
    public let wasAborted: Bool

    /// All successful results joined for LLM synthesis
    public var synthesisContext: String {
        stepResults
            .compactMap { result -> String? in
                guard case .completed(let output) = result.status else { return nil }
                return "[\(result.label)] \(output)"
            }
            .joined(separator: "\n\n")
    }

    /// Whether all non-optional steps succeeded and the chain was not aborted
    public var isSuccess: Bool {
        !wasAborted && stepResults.allSatisfy { result in
            switch result.status {
            case .completed, .skipped: return true
            case .failed: return result.isOptional
            case .pending, .running: return false
            }
        }
    }
}

/// Result for an individual step
public struct StepResult: Sendable {
    public let stepId: UUID
    public let toolName: String
    public let label: String
    public let status: ChainStepStatus
    public let isOptional: Bool
}

// MARK: - Built-in Chains

extension ToolChain {
    static let builtIn: [ToolChain] = [
        ToolChain(
            id: "travel_prep",
            name: "Travel Prep",
            description: "Weather, calendar, and packing reminders for your trip",
            icon: "airplane",
            steps: [
                ToolChainStep(
                    toolName: "calendar",
                    argumentTemplate: "{\"action\":\"list\"}",
                    label: "Check upcoming events"
                ),
                ToolChainStep(
                    toolName: "weather",
                    argumentTemplate: "{}",
                    label: "Get weather forecast"
                ),
                ToolChainStep(
                    toolName: "reminders",
                    argumentTemplate: "{\"action\":\"list\"}",
                    label: "Review packing reminders",
                    isOptional: true
                ),
            ],
            createdAt: Date(timeIntervalSince1970: 0)
        ),
        ToolChain(
            id: "daily_digest",
            name: "Daily Digest",
            description: "Weather, schedule, and reminders at a glance",
            icon: "newspaper",
            steps: [
                ToolChainStep(
                    toolName: "weather",
                    argumentTemplate: "{}",
                    label: "Current weather"
                ),
                ToolChainStep(
                    toolName: "calendar",
                    argumentTemplate: "{\"action\":\"list\"}",
                    label: "Today's events"
                ),
                ToolChainStep(
                    toolName: "reminders",
                    argumentTemplate: "{\"action\":\"list\"}",
                    label: "Pending reminders"
                ),
            ],
            createdAt: Date(timeIntervalSince1970: 0)
        ),
        ToolChain(
            id: "meeting_context",
            name: "Meeting Context",
            description: "Event details, attendees, and meeting location weather",
            icon: "person.3",
            steps: [
                ToolChainStep(
                    toolName: "calendar",
                    argumentTemplate: "{\"action\":\"list\"}",
                    label: "Get next meeting details"
                ),
                ToolChainStep(
                    toolName: "contacts",
                    argumentTemplate: "{\"query\":\"$0\"}",
                    label: "Look up attendees"
                ),
                ToolChainStep(
                    toolName: "weather",
                    argumentTemplate: "{}",
                    label: "Weather at meeting location",
                    isOptional: true
                ),
            ],
            createdAt: Date(timeIntervalSince1970: 0)
        ),
        ToolChain(
            id: "research_save",
            name: "Research & Save",
            description: "Fetch a URL and save key findings to memory",
            icon: "doc.text.magnifyingglass",
            steps: [
                ToolChainStep(
                    toolName: "web_fetch",
                    argumentTemplate: "{\"url\":\"$input\"}",
                    label: "Fetch web content"
                ),
                ToolChainStep(
                    toolName: "remember",
                    argumentTemplate: "{\"content\":\"$0\"}",
                    label: "Save key findings"
                ),
            ],
            createdAt: Date(timeIntervalSince1970: 0)
        ),
    ]

    /// All available chains (built-in + custom)
    static func allChains() async -> [ToolChain] {
        let custom = await ToolChainStore.shared.load()
        return builtIn + custom
    }
}
