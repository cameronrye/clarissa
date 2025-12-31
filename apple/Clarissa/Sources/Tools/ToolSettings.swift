import Foundation
import SwiftUI

/// Metadata for a tool displayed in settings
struct ToolInfo: Identifiable, Sendable {
    let id: String  // Tool name
    let name: String  // Display name
    let description: String
    let icon: String  // SF Symbol name
    var isEnabled: Bool
}

/// Maximum number of tools that can be enabled for Apple Intelligence (on-device)
/// Apple's guide recommends 3-5 max to avoid confusing the model
/// Set to 5 to accommodate all commonly-used default tools (weather, calendar, contacts, reminders, calculator)
let maxToolsForFoundationModels = 5

/// Default tool definitions
private let defaultToolDefinitions: [ToolInfo] = [
    ToolInfo(id: "weather", name: "Weather", description: "Get weather forecasts", icon: "cloud.sun", isEnabled: true),
    ToolInfo(id: "calendar", name: "Calendar", description: "Manage calendar events", icon: "calendar", isEnabled: true),
    ToolInfo(id: "contacts", name: "Contacts", description: "Search contacts", icon: "person.crop.circle", isEnabled: true),
    ToolInfo(id: "reminders", name: "Reminders", description: "Create and manage reminders", icon: "checklist", isEnabled: true),
    ToolInfo(id: "calculator", name: "Calculator", description: "Math calculations", icon: "function", isEnabled: true),
    ToolInfo(id: "location", name: "Location", description: "Get current location", icon: "location", isEnabled: false),
    ToolInfo(id: "web_fetch", name: "Web Fetch", description: "Fetch web content", icon: "globe", isEnabled: false),
    ToolInfo(id: "remember", name: "Memory", description: "Remember information", icon: "brain", isEnabled: false),
]

/// Manages tool configuration and persistence
@MainActor
final class ToolSettings: ObservableObject, @unchecked Sendable {
    static let shared = ToolSettings()

    private let enabledToolsKey = "enabledTools"

    /// All available tools with their metadata
    @Published private(set) var allTools: [ToolInfo]

    /// Currently enabled tool names
    @Published private(set) var enabledToolNames: Set<String>

    private init() {
        // Initialize with default tools first
        var tools = defaultToolDefinitions
        var enabledNames: Set<String>

        // Load saved enabled tools, or use defaults
        if let savedEnabled = UserDefaults.standard.array(forKey: enabledToolsKey) as? [String] {
            enabledNames = Set(savedEnabled)
            // Update isEnabled for each tool
            for i in tools.indices {
                tools[i].isEnabled = enabledNames.contains(tools[i].id)
            }
        } else {
            // Default enabled tools
            enabledNames = Set(tools.filter { $0.isEnabled }.map { $0.id })
        }

        self.allTools = tools
        self.enabledToolNames = enabledNames
    }
    
    /// Save settings to UserDefaults
    private func saveSettings() {
        UserDefaults.standard.set(Array(enabledToolNames), forKey: enabledToolsKey)
    }
    
    /// Toggle a tool's enabled state
    /// Returns false if the tool could not be enabled due to the limit being reached
    @discardableResult
    func toggleTool(_ toolId: String) -> Bool {
        if enabledToolNames.contains(toolId) {
            enabledToolNames.remove(toolId)
        } else {
            // Check if we're at the limit before adding
            guard enabledToolNames.count < maxToolsForFoundationModels else {
                return false
            }
            enabledToolNames.insert(toolId)
        }

        // Update the allTools array
        if let index = allTools.firstIndex(where: { $0.id == toolId }) {
            allTools[index].isEnabled = enabledToolNames.contains(toolId)
        }

        saveSettings()
        return true
    }

    /// Set a tool's enabled state directly
    /// Returns false if the tool could not be enabled due to the limit being reached
    @discardableResult
    func setToolEnabled(_ toolId: String, enabled: Bool) -> Bool {
        if enabled {
            // Check if we're at the limit before adding
            guard !enabledToolNames.contains(toolId) && enabledToolNames.count < maxToolsForFoundationModels else {
                if enabledToolNames.contains(toolId) {
                    // Already enabled, no change needed
                    return true
                }
                return false
            }
            enabledToolNames.insert(toolId)
        } else {
            enabledToolNames.remove(toolId)
        }

        // Update the allTools array
        if let index = allTools.firstIndex(where: { $0.id == toolId }) {
            allTools[index].isEnabled = enabled
        }

        saveSettings()
        return true
    }
    
    /// Check if a tool is enabled
    func isToolEnabled(_ toolId: String) -> Bool {
        enabledToolNames.contains(toolId)
    }
    
    /// Number of currently enabled tools
    var enabledCount: Int {
        enabledToolNames.count
    }
    
    /// Whether we're at the limit for Foundation Models
    var isAtFoundationModelsLimit: Bool {
        enabledToolNames.count >= maxToolsForFoundationModels
    }
}

