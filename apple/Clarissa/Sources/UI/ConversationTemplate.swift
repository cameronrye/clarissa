import Foundation

/// A pre-built conversation starter with specialized system prompt, tools, and response tuning
struct ConversationTemplate: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let description: String
    let icon: String  // SF Symbol name

    /// Additional system prompt instruction appended to the base prompt
    let systemPromptFocus: String?

    /// Specific tool names to enable for this template (nil = use current settings)
    let toolNames: [String]?

    /// Override for maxResponseTokens (nil = use default)
    let maxResponseTokens: Int?

    /// Initial message to send when template is selected (nil = just configure, don't auto-send)
    let initialPrompt: String?

    /// Whether this is a user-created custom template
    var isCustom: Bool { !ConversationTemplate.bundled.contains(where: { $0.id == id }) }
}

// MARK: - All Templates

extension ConversationTemplate {
    /// Returns bundled + custom templates
    static func allTemplates() async -> [ConversationTemplate] {
        let custom = await TemplateStore.shared.load()
        return bundled + custom
    }
}

// MARK: - Custom Template Persistence

/// Persists user-created templates as JSON in the app's documents directory
actor TemplateStore {
    static let shared = TemplateStore()

    private let fileName = "custom_templates.json"

    private var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(fileName)
    }

    func load() -> [ConversationTemplate] {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let templates = try? JSONDecoder().decode([ConversationTemplate].self, from: data) else {
            return []
        }
        return templates
    }

    func save(_ templates: [ConversationTemplate]) throws {
        let data = try JSONEncoder().encode(templates)
        try data.write(to: fileURL, options: .atomic)
    }

    func add(_ template: ConversationTemplate) throws {
        var templates = load()
        templates.append(template)
        try save(templates)
    }

    func delete(id: String) throws {
        var templates = load()
        templates.removeAll { $0.id == id }
        try save(templates)
    }

    func update(_ template: ConversationTemplate) throws {
        var templates = load()
        if let index = templates.firstIndex(where: { $0.id == template.id }) {
            templates[index] = template
        }
        try save(templates)
    }
}

// MARK: - Bundled Templates

extension ConversationTemplate {
    /// Built-in templates shipped with the app
    static let bundled: [ConversationTemplate] = [
        ConversationTemplate(
            id: "morning_briefing",
            name: "Morning Briefing",
            description: "Weather, calendar, and reminders summary",
            icon: "sunrise",
            systemPromptFocus: "Give a concise morning briefing. Lead with weather, then today's events, then pending reminders. Use a friendly, energizing tone.",
            toolNames: ["weather", "calendar", "reminders"],
            maxResponseTokens: 600,
            initialPrompt: "Give me my morning briefing"
        ),
        ConversationTemplate(
            id: "meeting_prep",
            name: "Meeting Prep",
            description: "Event details and attendee info",
            icon: "person.2",
            systemPromptFocus: "Help prepare for meetings. Show event details, attendee contact info, and suggest talking points. Be organized and thorough.",
            toolNames: ["calendar", "contacts"],
            maxResponseTokens: 500,
            initialPrompt: "Help me prepare for my next meeting"
        ),
        ConversationTemplate(
            id: "research_mode",
            name: "Research Mode",
            description: "Web search with longer responses",
            icon: "magnifyingglass",
            systemPromptFocus: "Help with research. Give detailed, well-structured responses. Save key findings to memory. Include sources when fetching web content.",
            toolNames: ["web_fetch", "remember"],
            maxResponseTokens: 800,
            initialPrompt: nil
        ),
        ConversationTemplate(
            id: "quick_math",
            name: "Quick Math",
            description: "Fast calculations, minimal chat",
            icon: "function",
            systemPromptFocus: "Focus on math and calculations. Give the answer immediately with minimal explanation. Show the calculation steps only if asked.",
            toolNames: ["calculator"],
            maxResponseTokens: 200,
            initialPrompt: nil
        ),
    ]
}
