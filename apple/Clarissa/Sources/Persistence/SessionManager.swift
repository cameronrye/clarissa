import Foundation
import os.log

/// Manages conversation sessions
actor SessionManager {
    static let shared = SessionManager()

    private var sessions: [Session] = []
    private var currentSessionId: UUID?
    private let fileURL: URL
    private var isLoaded = false

    /// Maximum number of messages to keep per session
    static let maxMessagesPerSession = ClarissaConstants.maxMessagesPerSession

    /// Maximum number of sessions to keep
    static let maxSessions = ClarissaConstants.maxSessions

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
        ClarissaLogger.persistence.info("Started new session: \(session.id.uuidString, privacy: .public)")

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

        // Trim messages using token-budget-based limit instead of hard message count.
        // Keep removing oldest non-system messages until within budget, with a hard cap as safety net.
        var trimmedMessages = messages
        let maxTokens = TokenBudget.maxHistoryTokens
        var tokenCount = TokenBudget.estimate(trimmedMessages.filter { $0.role != .system })

        // Remove oldest non-system messages while over budget (keep last 3 as minimum)
        while tokenCount > maxTokens {
            let nonSystemIndices = trimmedMessages.indices.filter { trimmedMessages[$0].role != .system }
            guard nonSystemIndices.count > 3, let oldest = nonSystemIndices.first else { break }
            let removed = trimmedMessages.remove(at: oldest)
            tokenCount -= TokenBudget.estimate(removed.content)
        }

        // Safety net: hard cap at maxMessagesPerSession to prevent unbounded storage
        if trimmedMessages.count > Self.maxMessagesPerSession {
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

    /// Rename a session
    func renameSession(id: UUID, newTitle: String) async {
        await ensureLoaded()

        guard let index = sessions.firstIndex(where: { $0.id == id }) else {
            ClarissaLogger.persistence.error("Session not found for rename: \(id.uuidString, privacy: .public)")
            return
        }

        let trimmedTitle = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            ClarissaLogger.persistence.warning("Cannot rename session to empty title")
            return
        }

        sessions[index].title = trimmedTitle
        sessions[index].updatedAt = Date()
        ClarissaLogger.persistence.info("Renamed session to: \(trimmedTitle, privacy: .public)")
        await save()
    }

    /// Tag a session with topics extracted from user messages
    func tagSession(id: UUID) async {
        await ensureLoaded()

        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }

        // Skip if already tagged
        if sessions[index].topics != nil { return }

        // Collect first 3 user messages for topic extraction
        let userContent = sessions[index].messages
            .filter { $0.role == .user }
            .prefix(3)
            .map { $0.content }
            .joined(separator: " ")

        guard !userContent.isEmpty else { return }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            do {
                let topics = try await MainActor.run {
                    Task { try await ContentTagger.shared.extractTopics(from: userContent) }
                }.value
                sessions[index].topics = topics.isEmpty ? nil : topics
                await save()
                ClarissaLogger.persistence.info("Tagged session with topics: \(topics)")
            } catch {
                ClarissaLogger.persistence.warning("Failed to tag session: \(error.localizedDescription)")
            }
        }
        #endif
    }

    /// Get all unique topics across all sessions for filter UI
    func getAllTopics() async -> [String] {
        await ensureLoaded()
        var topicSet = Set<String>()
        for session in sessions {
            if let topics = session.topics {
                topicSet.formUnion(topics)
            }
        }
        return topicSet.sorted()
    }

    /// Get the current session ID
    func getCurrentSessionId() async -> UUID? {
        await ensureLoaded()
        return currentSessionId
    }

    /// Switch to a different session
    func switchToSession(id: UUID) async -> Session? {
        await ensureLoaded()

        guard let session = sessions.first(where: { $0.id == id }) else {
            ClarissaLogger.persistence.error("Session not found: \(id.uuidString, privacy: .public)")
            return nil
        }

        ClarissaLogger.persistence.info(
            "Switching to session '\(session.title, privacy: .public)' with \(session.messages.count) total messages"
        )

        currentSessionId = id
        await save() // Persist the session switch immediately
        return session
    }

    /// Trim old sessions to stay under limit
    private func trimOldSessions() {
        if sessions.count > Self.maxSessions {
            let toRemove = sessions.count - Self.maxSessions
            sessions.removeLast(toRemove)
            ClarissaLogger.persistence.info("Trimmed \(toRemove) old sessions")
        }
    }

    private func load() async {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            ClarissaLogger.persistence.info("No sessions file found, starting fresh")
            isLoaded = true
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()

            // Try to decode new format with currentSessionId first
            if let persistedData = try? decoder.decode(PersistedSessionData.self, from: data) {
                sessions = persistedData.sessions
                // Restore the persisted currentSessionId, or fall back to first session
                if let savedId = persistedData.currentSessionId,
                   sessions.contains(where: { $0.id == savedId }) {
                    currentSessionId = savedId
                } else {
                    currentSessionId = sessions.first?.id
                }
            } else {
                // Fall back to old format (array of sessions only) for migration
                sessions = try decoder.decode([Session].self, from: data)
                currentSessionId = sessions.first?.id
                ClarissaLogger.persistence.info("Migrated from old session format")
            }

            isLoaded = true

            // Log details about loaded sessions
            for session in sessions {
                let userMessages = session.messages.filter { $0.role == .user }.count
                let assistantMessages = session.messages.filter { $0.role == .assistant }.count
                ClarissaLogger.persistence.info(
                    "Session '\(session.title, privacy: .public)': \(session.messages.count) total (\(userMessages) user, \(assistantMessages) assistant)"
                )
            }
            ClarissaLogger.persistence.info("Loaded \(self.sessions.count) sessions total, active: \(self.currentSessionId?.uuidString ?? "none", privacy: .public)")
        } catch {
            ClarissaLogger.persistence.error("Failed to load sessions: \(error.localizedDescription)")
            isLoaded = true
        }
    }

    private func save() async {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let persistedData = PersistedSessionData(sessions: sessions, currentSessionId: currentSessionId)
            let data = try encoder.encode(persistedData)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            ClarissaLogger.persistence.error("Failed to save sessions: \(error.localizedDescription)")
        }
    }
}

/// Wrapper for persisted session data including the active session ID
private struct PersistedSessionData: Codable {
    let sessions: [Session]
    let currentSessionId: UUID?
}

/// A conversation session
struct Session: Identifiable, Codable {
    let id: UUID
    var title: String
    var messages: [Message]
    let createdAt: Date
    var updatedAt: Date
    /// Topics extracted via ContentTagger for search/filtering
    var topics: [String]?

    init(
        id: UUID = UUID(),
        title: String = "New Conversation",
        messages: [Message] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        topics: [String]? = nil
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.topics = topics
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

