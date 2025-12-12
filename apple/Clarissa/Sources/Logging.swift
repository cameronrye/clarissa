import Foundation
import os.log

/// Centralized logging for Clarissa
enum ClarissaLogger {
    /// Logger for agent-related operations
    static let agent = Logger(subsystem: "dev.rye.Clarissa", category: "Agent")

    /// Logger for LLM provider operations
    static let provider = Logger(subsystem: "dev.rye.Clarissa", category: "Provider")

    /// Logger for tool execution
    static let tools = Logger(subsystem: "dev.rye.Clarissa", category: "Tools")

    /// Logger for persistence operations
    static let persistence = Logger(subsystem: "dev.rye.Clarissa", category: "Persistence")

    /// Logger for UI-related events
    static let ui = Logger(subsystem: "dev.rye.Clarissa", category: "UI")

    /// Logger for network operations
    static let network = Logger(subsystem: "dev.rye.Clarissa", category: "Network")
}

