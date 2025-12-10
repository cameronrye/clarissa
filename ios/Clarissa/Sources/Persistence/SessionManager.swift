import Foundation
import os.log

private let logger = Logger(subsystem: "dev.rye.Clarissa", category: "SessionManager")

/// Manages conversation sessions
actor SessionManager {
    static let shared = SessionManager()

    private var sessions: [Session] = []
    private var currentSessionId: UUID?
    private let fileURL: URL
    private var isLoaded = false

    /// Maximum number of messages to keep per session
    static let maxMessagesPerSession = 100

    /// Maximum number of sessions to keep
    static let maxSessions = 50

    private init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.fileURL = documentsPath.appendingPathComponent("clarissa_sessions.json")
    }

    /// Ensure data is loaded before accessing
    private func ensureLoaded() async {
        if !isLoaded {
            await load()
        }
    }

    /// Get or create the current session
    func getCurrentSession() async -> Session {
        await ensureLoaded()

        if let id = currentSessionId, let session = sessions.first(where: { $0.id == id }) {
            return session
        }

        // Create new session
        let session = Session()
        sessions.insert(session, at: 0)
        currentSessionId = session.id
        await save()
        return session
    }

    /// Start a new session
    func startNewSession() async -> Session {
        await ensureLoaded()

        let session = Session()
        sessions.insert(session, at: 0)
        currentSessionId = session.id

        // Trim old sessions if needed
        trimOldSessions()

        await save()
        return session
    }

    /// Update the current session with new messages
    func updateCurrentSession(messages: [Message]) async {
        await ensureLoaded()

        guard let id = currentSessionId,
              let index = sessions.firstIndex(where: { $0.id == id }) else {
            return
        }

        // Trim messages if needed
        var trimmedMessages = messages
        if trimmedMessages.count > Self.maxMessagesPerSession {
            // Keep system message and most recent messages
            let systemMessages = trimmedMessages.filter { $0.role == .system }
            let otherMessages = trimmedMessages.filter { $0.role != .system }
            let recentMessages = Array(otherMessages.suffix(Self.maxMessagesPerSession - systemMessages.count))
            trimmedMessages = systemMessages + recentMessages
        }

        sessions[index].messages = trimmedMessages
        sessions[index].updatedAt = Date()

        // Auto-generate title if still default
        if sessions[index].title == "New Conversation" {
            sessions[index].generateTitle()
        }

        await save()
    }

    /// Get all sessions
    func getAllSessions() async -> [Session] {
        await ensureLoaded()
        return sessions
    }

    /// Delete a session
    func deleteSession(id: UUID) async {
        await ensureLoaded()

        sessions.removeAll { $0.id == id }
        if currentSessionId == id {
            currentSessionId = sessions.first?.id
        }
        await save()
    }

    /// Switch to a different session
    func switchToSession(id: UUID) async -> Session? {
        await ensureLoaded()

        guard let session = sessions.first(where: { $0.id == id }) else {
            return nil
        }
        currentSessionId = id
        return session
    }

    /// Trim old sessions to stay under limit
    private func trimOldSessions() {
        if sessions.count > Self.maxSessions {
            let toRemove = sessions.count - Self.maxSessions
            sessions.removeLast(toRemove)
            logger.info("Trimmed \(toRemove) old sessions")
        }
    }

    private func load() async {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            isLoaded = true
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            sessions = try JSONDecoder().decode([Session].self, from: data)
            currentSessionId = sessions.first?.id
            isLoaded = true
            logger.info("Loaded \(self.sessions.count) sessions")
        } catch {
            logger.error("Failed to load sessions: \(error.localizedDescription)")
            isLoaded = true
        }
    }

    private func save() async {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(sessions)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to save sessions: \(error.localizedDescription)")
        }
    }
}

/// A conversation session
struct Session: Identifiable, Codable {
    let id: UUID
    var title: String
    var messages: [Message]
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "New Conversation",
        messages: [Message] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Generate a title from the first user message
    mutating func generateTitle() {
        if let firstUserMessage = messages.first(where: { $0.role == .user }) {
            let content = firstUserMessage.content
            // Clean up the title - remove newlines and extra spaces
            let cleanContent = content
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            title = String(cleanContent.prefix(50)) + (cleanContent.count > 50 ? "..." : "")
        }
    }
}

