import Foundation
import os.log

/// Centralized logging for Clarissa
public enum ClarissaLogger {
    /// Logger for agent-related operations
    public static let agent = Logger(subsystem: "dev.rye.Clarissa", category: "Agent")

    /// Logger for LLM provider operations
    public static let provider = Logger(subsystem: "dev.rye.Clarissa", category: "Provider")

    /// Logger for tool execution
    public static let tools = Logger(subsystem: "dev.rye.Clarissa", category: "Tools")

    /// Logger for persistence operations
    public static let persistence = Logger(subsystem: "dev.rye.Clarissa", category: "Persistence")

    /// Logger for UI-related events
    public static let ui = Logger(subsystem: "dev.rye.Clarissa", category: "UI")

    /// Logger for network operations
    public static let network = Logger(subsystem: "dev.rye.Clarissa", category: "Network")
}

