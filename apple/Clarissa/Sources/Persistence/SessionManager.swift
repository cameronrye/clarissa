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
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.fileURL = documentsPath.appendingPathComponent("clarissa_sessions.json")
    }

    /// Internal init for testing with a custom file path
    init(fileURL: URL) {
        self.fileURL = fileURL
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
                let topics = try await ContentTagger.shared.extractTopics(from: userContent)
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

    // MARK: - Pin Messages

    /// Toggle pin state on a message within the current session
    func toggleMessagePin(messageId: UUID) async {
        await ensureLoaded()

        guard let sessionId = currentSessionId,
              let sessionIndex = sessions.firstIndex(where: { $0.id == sessionId }),
              let messageIndex = sessions[sessionIndex].messages.firstIndex(where: { $0.id == messageId }) else {
            return
        }

        let current = sessions[sessionIndex].messages[messageIndex].isPinned ?? false
        sessions[sessionIndex].messages[messageIndex].isPinned = !current
        sessions[sessionIndex].updatedAt = Date()
        ClarissaLogger.persistence.info("Toggled pin on message \(messageId.uuidString.prefix(8)): \(!current)")
        await save()
    }

    /// Get all pinned messages for the current session
    func getPinnedMessages() async -> [Message] {
        await ensureLoaded()

        guard let id = currentSessionId,
              let session = sessions.first(where: { $0.id == id }) else {
            return []
        }

        return session.messages.filter { $0.isPinned == true }
    }

    // MARK: - Favorites

    /// Toggle favorite state on a session
    func toggleFavorite(id: UUID) async {
        await ensureLoaded()

        guard let index = sessions.firstIndex(where: { $0.id == id }) else {
            ClarissaLogger.persistence.error("Session not found for favorite toggle: \(id.uuidString, privacy: .public)")
            return
        }

        let current = sessions[index].isFavorite ?? false
        sessions[index].isFavorite = !current
        sessions[index].updatedAt = Date()
        ClarissaLogger.persistence.info("Toggled favorite on session '\(self.sessions[index].title, privacy: .public)': \(!current)")
        await save()
    }

    /// Get all favorited sessions
    func getFavoriteSessions() async -> [Session] {
        await ensureLoaded()
        return sessions.filter { $0.isFavorite == true }
    }

    // MARK: - Manual Tags

    /// Add a manual tag to a session
    func addTag(_ tag: String, to sessionId: UUID) async {
        await ensureLoaded()

        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return }

        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }

        var tags = sessions[index].manualTags ?? []
        guard !tags.contains(trimmed) else { return }

        tags.append(trimmed)
        sessions[index].manualTags = tags
        sessions[index].updatedAt = Date()
        ClarissaLogger.persistence.info("Added tag '\(trimmed)' to session")
        await save()
    }

    /// Remove a manual tag from a session
    func removeTag(_ tag: String, from sessionId: UUID) async {
        await ensureLoaded()

        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }

        var tags = sessions[index].manualTags ?? []
        tags.removeAll { $0 == tag }
        sessions[index].manualTags = tags.isEmpty ? nil : tags
        sessions[index].updatedAt = Date()
        await save()
    }

    /// Get all unique tags (both auto-extracted topics and manual tags) for filter UI
    func getAllTags() async -> [String] {
        await ensureLoaded()
        var tagSet = Set<String>()
        for session in sessions {
            if let topics = session.topics {
                tagSet.formUnion(topics)
            }
            if let manualTags = session.manualTags {
                tagSet.formUnion(manualTags)
            }
        }
        return tagSet.sorted()
    }

    // MARK: - Session Summary

    /// Set the auto-generated summary for a session
    func setSummary(_ summary: String, for sessionId: UUID) async {
        await ensureLoaded()

        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }

        sessions[index].summary = summary
        sessions[index].updatedAt = Date()
        ClarissaLogger.persistence.info("Set summary for session '\(self.sessions[index].title, privacy: .public)'")
        await save()
    }

    /// Trim old sessions to stay under limit, preserving favorited sessions
    private func trimOldSessions() {
        if sessions.count > Self.maxSessions {
            // Separate favorites from non-favorites; only trim non-favorites
            let favorites = sessions.filter { $0.isFavorite == true }
            var nonFavorites = sessions.filter { $0.isFavorite != true }
            let targetNonFavorites = Self.maxSessions - favorites.count
            if nonFavorites.count > targetNonFavorites {
                let toRemove = nonFavorites.count - targetNonFavorites
                nonFavorites.removeLast(toRemove)
                ClarissaLogger.persistence.info("Trimmed \(toRemove) old sessions (preserved \(favorites.count) favorites)")
            }
            sessions = favorites + nonFavorites
            // Re-sort by updatedAt (most recent first)
            sessions.sort { $0.updatedAt > $1.updatedAt }
        }
    }

    private func load() async {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            ClarissaLogger.persistence.info("No sessions file found, starting fresh")
            isLoaded = true
            return
        }

        do {
            var data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()

            // Run schema migrations if needed
            let detectedVersion = SchemaMigrator.detectVersion(from: data)
            if detectedVersion < .current {
                ClarissaLogger.persistence.info("Migrating sessions from schema v\(detectedVersion.rawValue) to v\(SchemaVersion.current.rawValue)")
                data = try SchemaMigrator.migrate(data: data)
            }

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

            // Re-save if we migrated to persist the new schema version
            if detectedVersion < .current {
                await save()
            }

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
            // Backup corrupted file for diagnostics before discarding
            let backupURL = fileURL.deletingLastPathComponent().appendingPathComponent("sessions_corrupted_\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: fileURL, to: backupURL)
            isLoaded = true
        }
    }

    private func save() async {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let persistedData = PersistedSessionData(sessions: sessions, currentSessionId: currentSessionId)
            let data = try encoder.encode(persistedData)
            let url = fileURL
            let dir = url.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            try data.write(to: url, options: .atomic)
        } catch {
            ClarissaLogger.persistence.error("Failed to save sessions: \(error.localizedDescription)")
        }
    }
}

/// Wrapper for persisted session data including the active session ID and schema version
struct PersistedSessionData: Codable {
    let schemaVersion: SchemaVersion?
    let sessions: [Session]
    let currentSessionId: UUID?

    init(sessions: [Session], currentSessionId: UUID?) {
        self.schemaVersion = .current
        self.sessions = sessions
        self.currentSessionId = currentSessionId
    }
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
    /// User-starred session (kept from being lost in history)
    var isFavorite: Bool?
    /// Auto-generated one-line conversation summary
    var summary: String?
    /// User-applied tags (distinct from auto-extracted topics)
    var manualTags: [String]?

    init(
        id: UUID = UUID(),
        title: String = "New Conversation",
        messages: [Message] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        topics: [String]? = nil,
        isFavorite: Bool? = nil,
        summary: String? = nil,
        manualTags: [String]? = nil
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.topics = topics
        self.isFavorite = isFavorite
        self.summary = summary
        self.manualTags = manualTags
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

    /// All tags: auto-extracted topics + user-applied manual tags, deduplicated
    var allTags: [String] {
        var tagSet = Set<String>()
        if let topics { tagSet.formUnion(topics) }
        if let manualTags { tagSet.formUnion(manualTags) }
        return tagSet.sorted()
    }
}

