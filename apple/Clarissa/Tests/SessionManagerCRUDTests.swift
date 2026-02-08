import Foundation
import Testing
@testable import ClarissaKit

// MARK: - SessionManager CRUD Tests

@Suite("SessionManager CRUD Tests")
struct SessionManagerCRUDTests {

    /// Create a fresh SessionManager using a temp file for isolated testing
    private func makeManager() -> SessionManager {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test_sessions_\(UUID().uuidString).json")
        return SessionManager(fileURL: fileURL)
    }

    @Test("getCurrentSession creates a new session when none exist")
    func testGetCurrentSessionCreatesNew() async {
        let manager = makeManager()
        let session = await manager.getCurrentSession()

        #expect(session.title == "New Conversation")
        #expect(session.messages.isEmpty)

        let all = await manager.getAllSessions()
        #expect(all.count == 1)
        #expect(all[0].id == session.id)
    }

    @Test("getCurrentSession returns the same session on repeated calls")
    func testGetCurrentSessionIdempotent() async {
        let manager = makeManager()
        let first = await manager.getCurrentSession()
        let second = await manager.getCurrentSession()

        #expect(first.id == second.id)

        let all = await manager.getAllSessions()
        #expect(all.count == 1)
    }

    @Test("startNewSession creates a distinct session")
    func testStartNewSession() async {
        let manager = makeManager()
        let first = await manager.getCurrentSession()
        let second = await manager.startNewSession()

        #expect(first.id != second.id)
        #expect(second.title == "New Conversation")

        let all = await manager.getAllSessions()
        #expect(all.count == 2)
    }

    @Test("startNewSession sets currentSessionId to new session")
    func testStartNewSessionUpdatesCurrent() async {
        let manager = makeManager()
        _ = await manager.getCurrentSession()
        let newSession = await manager.startNewSession()

        let currentId = await manager.getCurrentSessionId()
        #expect(currentId == newSession.id)
    }

    @Test("updateCurrentSession stores messages")
    func testUpdateCurrentSessionMessages() async {
        let manager = makeManager()
        _ = await manager.getCurrentSession()

        let messages: [Message] = [
            .user("Hello"),
            .assistant("Hi there!")
        ]
        await manager.updateCurrentSession(messages: messages)

        let updated = await manager.getCurrentSession()
        #expect(updated.messages.count == 2)
        #expect(updated.messages[0].content == "Hello")
        #expect(updated.messages[1].content == "Hi there!")
    }

    @Test("updateCurrentSession auto-generates title from first user message")
    func testUpdateGeneratesTitle() async {
        let manager = makeManager()
        _ = await manager.getCurrentSession()

        let messages: [Message] = [
            .user("What is the weather like today?"),
            .assistant("It's sunny and 72F.")
        ]
        await manager.updateCurrentSession(messages: messages)

        let updated = await manager.getCurrentSession()
        #expect(updated.title != "New Conversation")
        #expect(updated.title.contains("What is the weather"))
    }

    @Test("deleteSession removes the session")
    func testDeleteSession() async {
        let manager = makeManager()
        let session = await manager.getCurrentSession()

        await manager.deleteSession(id: session.id)

        let all = await manager.getAllSessions()
        #expect(all.isEmpty)
    }

    @Test("deleteSession switches currentSessionId when active session is deleted")
    func testDeleteActiveSessionSwitches() async {
        let manager = makeManager()
        let first = await manager.startNewSession()
        let second = await manager.startNewSession()

        // Current is second
        let currentBefore = await manager.getCurrentSessionId()
        #expect(currentBefore == second.id)

        // Delete the active session
        await manager.deleteSession(id: second.id)

        let currentAfter = await manager.getCurrentSessionId()
        #expect(currentAfter == first.id)
    }

    @Test("switchToSession changes active session")
    func testSwitchToSession() async {
        let manager = makeManager()
        let first = await manager.startNewSession()
        _ = await manager.startNewSession()

        // Switch back to the first session
        let switched = await manager.switchToSession(id: first.id)
        #expect(switched != nil)
        #expect(switched?.id == first.id)

        let currentId = await manager.getCurrentSessionId()
        #expect(currentId == first.id)
    }

    @Test("switchToSession returns nil for nonexistent ID")
    func testSwitchToNonexistentSession() async {
        let manager = makeManager()
        _ = await manager.getCurrentSession()

        let result = await manager.switchToSession(id: UUID())
        #expect(result == nil)
    }

    @Test("renameSession updates the title")
    func testRenameSession() async {
        let manager = makeManager()
        let session = await manager.getCurrentSession()

        await manager.renameSession(id: session.id, newTitle: "My Custom Title")

        let all = await manager.getAllSessions()
        #expect(all[0].title == "My Custom Title")
    }

    @Test("renameSession rejects empty title")
    func testRenameSessionRejectsEmpty() async {
        let manager = makeManager()
        let session = await manager.getCurrentSession()
        let originalTitle = session.title

        await manager.renameSession(id: session.id, newTitle: "   ")

        let all = await manager.getAllSessions()
        #expect(all[0].title == originalTitle)
    }

    @Test("renameSession trims whitespace")
    func testRenameSessionTrimsWhitespace() async {
        let manager = makeManager()
        let session = await manager.getCurrentSession()

        await manager.renameSession(id: session.id, newTitle: "  Trimmed Title  ")

        let all = await manager.getAllSessions()
        #expect(all[0].title == "Trimmed Title")
    }
}

// MARK: - SessionManager Pin Tests

@Suite("SessionManager Pin Tests")
struct SessionManagerPinTests {

    private func makeManager() -> SessionManager {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test_sessions_\(UUID().uuidString).json")
        return SessionManager(fileURL: fileURL)
    }

    @Test("toggleMessagePin pins and unpins a message")
    func testToggleMessagePin() async {
        let manager = makeManager()
        _ = await manager.getCurrentSession()

        let message = Message.user("Pin me")
        await manager.updateCurrentSession(messages: [message])

        // Pin
        await manager.toggleMessagePin(messageId: message.id)
        var pinned = await manager.getPinnedMessages()
        #expect(pinned.count == 1)
        #expect(pinned[0].id == message.id)

        // Unpin
        await manager.toggleMessagePin(messageId: message.id)
        pinned = await manager.getPinnedMessages()
        #expect(pinned.isEmpty)
    }

    @Test("getPinnedMessages returns empty when no pins")
    func testGetPinnedMessagesEmpty() async {
        let manager = makeManager()
        _ = await manager.getCurrentSession()

        let pinned = await manager.getPinnedMessages()
        #expect(pinned.isEmpty)
    }
}

// MARK: - SessionManager Favorite Tests

@Suite("SessionManager Favorite Tests")
struct SessionManagerFavoriteTests {

    private func makeManager() -> SessionManager {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test_sessions_\(UUID().uuidString).json")
        return SessionManager(fileURL: fileURL)
    }

    @Test("toggleFavorite marks and unmarks a session")
    func testToggleFavorite() async {
        let manager = makeManager()
        let session = await manager.getCurrentSession()

        // Favorite
        await manager.toggleFavorite(id: session.id)
        var favorites = await manager.getFavoriteSessions()
        #expect(favorites.count == 1)
        #expect(favorites[0].id == session.id)

        // Unfavorite
        await manager.toggleFavorite(id: session.id)
        favorites = await manager.getFavoriteSessions()
        #expect(favorites.isEmpty)
    }

    @Test("getFavoriteSessions returns only favorites")
    func testGetFavoriteSessions() async {
        let manager = makeManager()
        let session1 = await manager.startNewSession()
        _ = await manager.startNewSession()

        await manager.toggleFavorite(id: session1.id)

        let favorites = await manager.getFavoriteSessions()
        #expect(favorites.count == 1)
        #expect(favorites[0].id == session1.id)
    }
}

// MARK: - SessionManager Tag Tests

@Suite("SessionManager Tag Tests")
struct SessionManagerTagTests {

    private func makeManager() -> SessionManager {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test_sessions_\(UUID().uuidString).json")
        return SessionManager(fileURL: fileURL)
    }

    @Test("addTag adds a tag to a session")
    func testAddTag() async {
        let manager = makeManager()
        let session = await manager.getCurrentSession()

        await manager.addTag("important", to: session.id)

        let all = await manager.getAllSessions()
        #expect(all[0].manualTags == ["important"])
    }

    @Test("addTag normalizes to lowercase")
    func testAddTagNormalizesToLowercase() async {
        let manager = makeManager()
        let session = await manager.getCurrentSession()

        await manager.addTag("URGENT", to: session.id)

        let all = await manager.getAllSessions()
        #expect(all[0].manualTags == ["urgent"])
    }

    @Test("addTag rejects duplicates")
    func testAddTagRejectsDuplicate() async {
        let manager = makeManager()
        let session = await manager.getCurrentSession()

        await manager.addTag("bug", to: session.id)
        await manager.addTag("bug", to: session.id)

        let all = await manager.getAllSessions()
        #expect(all[0].manualTags?.count == 1)
    }

    @Test("addTag rejects empty/whitespace tags")
    func testAddTagRejectsEmpty() async {
        let manager = makeManager()
        let session = await manager.getCurrentSession()

        await manager.addTag("   ", to: session.id)
        await manager.addTag("", to: session.id)

        let all = await manager.getAllSessions()
        #expect(all[0].manualTags == nil)
    }

    @Test("removeTag removes a specific tag")
    func testRemoveTag() async {
        let manager = makeManager()
        let session = await manager.getCurrentSession()

        await manager.addTag("keep", to: session.id)
        await manager.addTag("remove", to: session.id)

        await manager.removeTag("remove", from: session.id)

        let all = await manager.getAllSessions()
        #expect(all[0].manualTags == ["keep"])
    }

    @Test("removeTag sets manualTags to nil when last tag removed")
    func testRemoveLastTagSetsNil() async {
        let manager = makeManager()
        let session = await manager.getCurrentSession()

        await manager.addTag("only", to: session.id)
        await manager.removeTag("only", from: session.id)

        let all = await manager.getAllSessions()
        #expect(all[0].manualTags == nil)
    }

    @Test("getAllTags returns union of topics and manualTags")
    func testGetAllTags() async {
        let manager = makeManager()
        let session = await manager.getCurrentSession()

        await manager.addTag("manual-tag", to: session.id)

        let allTags = await manager.getAllTags()
        #expect(allTags.contains("manual-tag"))
    }
}

// MARK: - SessionManager Summary Tests

@Suite("SessionManager Summary Tests")
struct SessionManagerSummaryTests {

    private func makeManager() -> SessionManager {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test_sessions_\(UUID().uuidString).json")
        return SessionManager(fileURL: fileURL)
    }

    @Test("setSummary stores summary on session")
    func testSetSummary() async {
        let manager = makeManager()
        let session = await manager.getCurrentSession()

        await manager.setSummary("A brief chat about weather", for: session.id)

        let all = await manager.getAllSessions()
        #expect(all[0].summary == "A brief chat about weather")
    }

    @Test("setSummary updates updatedAt")
    func testSetSummaryUpdatesTimestamp() async {
        let manager = makeManager()
        let session = await manager.getCurrentSession()
        let originalUpdatedAt = session.updatedAt

        // Small delay to ensure timestamp difference
        try? await Task.sleep(for: .milliseconds(50))

        await manager.setSummary("Summary text", for: session.id)

        let all = await manager.getAllSessions()
        #expect(all[0].updatedAt > originalUpdatedAt)
    }
}

// MARK: - SessionManager Persistence Tests

@Suite("SessionManager Persistence Tests")
struct SessionManagerPersistenceTests {

    private func makeTempFileURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        return tempDir.appendingPathComponent("test_sessions_\(UUID().uuidString).json")
    }

    @Test("Data persists across manager instances using same file")
    func testPersistenceAcrossInstances() async {
        let fileURL = makeTempFileURL()

        // Create and populate first instance
        let manager1 = SessionManager(fileURL: fileURL)
        let session = await manager1.startNewSession()
        await manager1.renameSession(id: session.id, newTitle: "Persisted Session")
        await manager1.addTag("test", to: session.id)

        // Create a new instance pointing to the same file
        let manager2 = SessionManager(fileURL: fileURL)
        let all = await manager2.getAllSessions()

        #expect(all.count == 1)
        #expect(all[0].title == "Persisted Session")
        #expect(all[0].manualTags == ["test"])

        // Clean up
        try? FileManager.default.removeItem(at: fileURL)
    }

    @Test("currentSessionId persists across instances")
    func testCurrentSessionIdPersists() async {
        let fileURL = makeTempFileURL()

        let manager1 = SessionManager(fileURL: fileURL)
        let session = await manager1.startNewSession()

        let manager2 = SessionManager(fileURL: fileURL)
        let currentId = await manager2.getCurrentSessionId()

        #expect(currentId == session.id)

        try? FileManager.default.removeItem(at: fileURL)
    }

    @Test("Empty file starts fresh with no sessions")
    func testEmptyFileStartsFresh() async {
        let fileURL = makeTempFileURL()

        let manager = SessionManager(fileURL: fileURL)
        let all = await manager.getAllSessions()

        #expect(all.isEmpty)
    }
}

// MARK: - PersistedSessionData Tests

@Suite("PersistedSessionData Tests")
struct PersistedSessionDataTests {

    @Test("PersistedSessionData encodes with current schema version")
    func testEncodesWithSchemaVersion() throws {
        let data = PersistedSessionData(sessions: [], currentSessionId: nil)
        let encoded = try JSONEncoder().encode(data)
        let json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]

        #expect(json["schemaVersion"] as? Int == SchemaVersion.current.rawValue)
    }

    @Test("PersistedSessionData round-trips via Codable")
    func testCodableRoundTrip() throws {
        let session = Session(title: "Test")
        let original = PersistedSessionData(sessions: [session], currentSessionId: session.id)

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PersistedSessionData.self, from: encoded)

        #expect(decoded.sessions.count == 1)
        #expect(decoded.sessions[0].title == "Test")
        #expect(decoded.currentSessionId == session.id)
        #expect(decoded.schemaVersion == .current)
    }
}
