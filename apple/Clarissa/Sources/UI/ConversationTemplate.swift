import Foundation

/// A pre-built conversation starter with specialized system prompt, tools, and response tuning
public struct ConversationTemplate: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let icon: String  // SF Symbol name

    /// Additional system prompt instruction appended to the base prompt
    public let systemPromptFocus: String?

    /// Specific tool names to enable for this template (nil = use current settings)
    public let toolNames: [String]?

    /// Override for maxResponseTokens (nil = use default)
    public let maxResponseTokens: Int?

    /// Initial message to send when template is selected (nil = just configure, don't auto-send)
    public let initialPrompt: String?

    /// Whether this is a user-created custom template
    var isCustom: Bool { !ConversationTemplate.bundled.contains(where: { $0.id == id }) }
}

// MARK: - All Templates

extension ConversationTemplate {
    /// Returns bundled + custom templates
    public static func allTemplates() async -> [ConversationTemplate] {
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
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
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
        let url = fileURL
        let dir = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try data.write(to: url, options: .atomic)
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
    public static let bundled: [ConversationTemplate] = [
        ConversationTemplate(
            id: "morning_briefing",
            name: "Morning Briefing",
            description: "Weather, calendar, and reminders summary",
            icon: "sunrise",
            systemPromptFocus: "Give a concise morning briefing using the PREFETCHED DATA provided. The weather, calendar, and reminders data has already been fetched for you — summarize it directly. Do NOT call tools again. Do NOT fabricate data beyond what was prefetched. If a section has no data, say \"nothing scheduled\" or \"no reminders\". Lead with weather, then events, then reminders. Friendly, energizing tone.",
            toolNames: ["weather", "calendar", "reminders"],
            maxResponseTokens: 600,
            initialPrompt: "Give me my morning briefing"
        ),
        ConversationTemplate(
            id: "meeting_prep",
            name: "Meeting Prep",
            description: "Event details and attendee info",
            icon: "person.2",
            systemPromptFocus: "Help prepare for meetings using the PREFETCHED DATA provided. Calendar and contacts data has already been fetched for you — summarize it directly. Do NOT call tools again. Do NOT fabricate event or attendee data beyond what was prefetched. Show event details, attendee contact info, and suggest talking points. Be organized and thorough.",
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
