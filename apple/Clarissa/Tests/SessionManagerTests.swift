import Foundation
import Testing
@testable import ClarissaKit

// MARK: - Suite 1: Schema Version Tests

@Suite("Schema Version Tests")
struct SchemaVersionTests {

    @Test("SchemaVersion.current is .v3")
    func testCurrentVersion() {
        #expect(SchemaVersion.current == .v3)
    }

    @Test("SchemaVersion comparison: .v1 < .v2")
    func testVersionComparison() {
        #expect(SchemaVersion.v1 < SchemaVersion.v2)
        #expect(!(SchemaVersion.v2 < SchemaVersion.v1))
        #expect(!(SchemaVersion.v1 < SchemaVersion.v1))
    }

    @Test("SchemaMigrator.detectVersion returns .v1 for data without schemaVersion field")
    func testDetectVersionReturnsV1ForLegacyData() throws {
        // Encode a simple JSON object that has no schemaVersion key
        let legacyDict: [String: String] = ["someKey": "someValue"]
        let data = try JSONEncoder().encode(legacyDict)

        let detected = SchemaMigrator.detectVersion(from: data)
        #expect(detected == .v1)
    }

    @Test("SchemaMigrator.detectVersion returns correct version for data with schemaVersion field")
    func testDetectVersionReturnsCorrectVersion() throws {
        // Manually construct JSON with schemaVersion = 2
        let json: [String: Any] = [
            "schemaVersion": 2,
            "sessions": [] as [Any],
            "currentSessionId": NSNull()
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        let detected = SchemaMigrator.detectVersion(from: data)
        #expect(detected == .v2)
    }

    @Test("SchemaMigrator.detectVersion returns .v1 for schemaVersion = 1")
    func testDetectVersionV1Explicit() throws {
        let json: [String: Any] = [
            "schemaVersion": 1,
            "sessions": [] as [Any]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        let detected = SchemaMigrator.detectVersion(from: data)
        #expect(detected == .v1)
    }

    @Test("SchemaMigrator.migrate from v1 is a no-op (data unchanged)")
    func testMigrateFromV1IsNoOp() throws {
        // Create v1-style data (no schemaVersion field) — just a JSON array of sessions
        let legacySessions: [[String: Any]] = [
            [
                "id": UUID().uuidString,
                "title": "Test Session",
                "messages": [] as [Any],
                "createdAt": ISO8601DateFormatter().string(from: Date()),
                "updatedAt": ISO8601DateFormatter().string(from: Date())
            ]
        ]
        let originalData = try JSONSerialization.data(withJSONObject: legacySessions)
        let migratedData = try SchemaMigrator.migrate(data: originalData)

        // v1 -> v2 migration is a pass-through, so data should be byte-identical
        #expect(originalData == migratedData)
    }
}

// MARK: - Suite 2: Session Data Model Tests

@Suite("Session Data Model Tests")
struct SessionDataModelTests {

    @Test("Session creation has expected defaults")
    func testSessionDefaults() {
        let session = Session()

        #expect(session.title == "New Conversation")
        #expect(session.messages.isEmpty)
        #expect(session.isFavorite == nil)
        #expect(session.summary == nil)
        #expect(session.manualTags == nil)
        #expect(session.topics == nil)
    }

    @Test("Session.allTags combines topics + manualTags and deduplicates")
    func testAllTagsCombinesAndDeduplicates() {
        let session = Session(
            topics: ["swift", "testing", "shared"],
            manualTags: ["important", "shared", "review"]
        )

        let allTags = session.allTags
        // Should contain all unique values, sorted
        #expect(allTags.contains("swift"))
        #expect(allTags.contains("testing"))
        #expect(allTags.contains("shared"))
        #expect(allTags.contains("important"))
        #expect(allTags.contains("review"))
        // "shared" appears in both but should only appear once
        #expect(allTags.filter { $0 == "shared" }.count == 1)
        // Should be sorted
        #expect(allTags == allTags.sorted())
        // Total unique count: swift, testing, shared, important, review = 5
        #expect(allTags.count == 5)
    }

    @Test("Session.allTags returns empty when both topics and manualTags are nil")
    func testAllTagsEmptyWhenBothNil() {
        let session = Session(topics: nil, manualTags: nil)
        #expect(session.allTags.isEmpty)
    }

    @Test("Session.allTags returns just topics when manualTags is nil")
    func testAllTagsReturnTopicsOnly() {
        let session = Session(topics: ["apple", "ios"], manualTags: nil)
        let allTags = session.allTags
        #expect(allTags.count == 2)
        #expect(allTags.contains("apple"))
        #expect(allTags.contains("ios"))
    }

    @Test("Session.allTags returns just manualTags when topics is nil")
    func testAllTagsReturnManualTagsOnly() {
        let session = Session(topics: nil, manualTags: ["urgent", "bug"])
        let allTags = session.allTags
        #expect(allTags.count == 2)
        #expect(allTags.contains("urgent"))
        #expect(allTags.contains("bug"))
    }

    @Test("Session.generateTitle uses first user message")
    func testGenerateTitle() {
        var session = Session(messages: [
            .user("What is the weather like today in San Francisco?")
        ])
        session.generateTitle()
        #expect(session.title.contains("What is the weather"))
        #expect(session.title.count <= 53) // 50 chars + "..."
    }

    @Test("Session round-trips via Codable")
    func testSessionCodable() throws {
        let session = Session(
            title: "Test Session",
            messages: [.user("Hello"), .assistant("Hi!")],
            topics: ["greeting"],
            isFavorite: true,
            summary: "A greeting session",
            manualTags: ["test"]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(session)
        let decoded = try JSONDecoder().decode(Session.self, from: data)

        #expect(decoded.id == session.id)
        #expect(decoded.title == session.title)
        #expect(decoded.messages.count == 2)
        #expect(decoded.topics == ["greeting"])
        #expect(decoded.isFavorite == true)
        #expect(decoded.summary == "A greeting session")
        #expect(decoded.manualTags == ["test"])
    }
}

// MARK: - Suite 3: Message Pin Tests

@Suite("Message Pin Tests")
struct MessagePinTests {

    @Test("Message can have isPinned set to true")
    func testMessagePinned() {
        let message = Message(role: .user, content: "Important note", isPinned: true)
        #expect(message.isPinned == true)
    }

    @Test("Message defaults to nil isPinned")
    func testMessageDefaultPinNil() {
        let message = Message.user("Hello")
        #expect(message.isPinned == nil)
    }

    @Test("Message with isPinned round-trips via Codable")
    func testMessagePinnedCodable() throws {
        let original = Message(role: .assistant, content: "Pinned reply", isPinned: true)

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(Message.self, from: data)

        #expect(decoded.isPinned == true)
        #expect(decoded.content == "Pinned reply")
        #expect(decoded.role == .assistant)
        #expect(decoded.id == original.id)
    }

    @Test("Legacy Message JSON without isPinned decodes correctly (backward compat)")
    func testLegacyMessageDecodesWithoutIsPinned() throws {
        // Construct JSON that mimics a pre-v2.1 Message (no isPinned field)
        let id = UUID()
        let timestamp = Date().timeIntervalSinceReferenceDate
        let json: [String: Any] = [
            "id": id.uuidString,
            "role": "user",
            "content": "Legacy message",
            "createdAt": timestamp
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(Message.self, from: data)
        #expect(decoded.isPinned == nil)
        #expect(decoded.content == "Legacy message")
        #expect(decoded.role == .user)
    }

    @Test("Message with isPinned = false round-trips correctly")
    func testMessagePinnedFalseCodable() throws {
        let original = Message(role: .user, content: "Not pinned", isPinned: false)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Message.self, from: data)

        #expect(decoded.isPinned == false)
    }
}

// MARK: - Suite 4: ChatMessage Pin Tests

@Suite("ChatMessage Pin Tests")
struct ChatMessagePinTests {

    @Test("ChatMessage has isPinned defaulting to false")
    func testChatMessageDefaultPin() {
        let chatMessage = ChatMessage(role: .user, content: "Hello")
        #expect(chatMessage.isPinned == false)
    }

    @Test("ChatMessage with isPinned = true works")
    func testChatMessagePinnedTrue() {
        var chatMessage = ChatMessage(role: .assistant, content: "Important response")
        chatMessage.isPinned = true
        #expect(chatMessage.isPinned == true)
    }

    @Test("ChatMessage preserves other properties when pin is toggled")
    func testChatMessagePinPreservesProperties() {
        var chatMessage = ChatMessage(role: .user, content: "Test content")
        let originalId = chatMessage.id
        let originalContent = chatMessage.content

        chatMessage.isPinned = true
        #expect(chatMessage.id == originalId)
        #expect(chatMessage.content == originalContent)
        #expect(chatMessage.role == .user)
    }
}

// MARK: - Suite 5: Analytics Collector Tests

@Suite("Analytics Collector Tests")
struct AnalyticsCollectorTests {

    @Test("AggregateMetrics default values")
    func testAggregateMetricsDefaults() {
        let metrics = AnalyticsCollector.AggregateMetrics()

        #expect(metrics.totalSessions == 0)
        #expect(metrics.crashFreeSessions == 0)
        #expect(metrics.totalToolCalls == 0)
        #expect(metrics.totalToolFailures == 0)
        #expect(metrics.totalReactIterations == 0)
        #expect(metrics.totalContextUsageSum == 0)
        // Computed properties with zero sessions should return safe defaults
        #expect(metrics.toolSuccessRate == 1.0)
        #expect(metrics.avgReactIterations == 0)
        #expect(metrics.crashFreeRate == 1.0)
        #expect(metrics.avgContextUtilization == 0)
    }

    @Test("toolSuccessRate computation with known values")
    func testToolSuccessRateComputation() {
        var metrics = AnalyticsCollector.AggregateMetrics()
        metrics.totalToolCalls = 100
        metrics.totalToolFailures = 10

        // Success rate = 1.0 - (10/100) = 0.9
        #expect(metrics.toolSuccessRate == 0.9)
    }

    @Test("toolSuccessRate is 1.0 when no failures")
    func testToolSuccessRateNoFailures() {
        var metrics = AnalyticsCollector.AggregateMetrics()
        metrics.totalToolCalls = 50
        metrics.totalToolFailures = 0

        #expect(metrics.toolSuccessRate == 1.0)
    }

    @Test("toolSuccessRate is 0.0 when all calls fail")
    func testToolSuccessRateAllFailures() {
        var metrics = AnalyticsCollector.AggregateMetrics()
        metrics.totalToolCalls = 20
        metrics.totalToolFailures = 20

        #expect(metrics.toolSuccessRate == 0.0)
    }

    @Test("avgReactIterations computation")
    func testAvgReactIterationsComputation() {
        var metrics = AnalyticsCollector.AggregateMetrics()
        metrics.totalSessions = 10
        metrics.totalReactIterations = 30

        // Average = 30 / 10 = 3.0
        #expect(metrics.avgReactIterations == 3.0)
    }

    @Test("avgReactIterations is 0 when no sessions")
    func testAvgReactIterationsZeroSessions() {
        let metrics = AnalyticsCollector.AggregateMetrics()
        #expect(metrics.avgReactIterations == 0)
    }

    @Test("crashFreeRate computation")
    func testCrashFreeRateComputation() {
        var metrics = AnalyticsCollector.AggregateMetrics()
        metrics.totalSessions = 100
        metrics.crashFreeSessions = 95

        // Crash-free rate = 95 / 100 = 0.95
        #expect(metrics.crashFreeRate == 0.95)
    }

    @Test("crashFreeRate is 1.0 when all sessions crash-free")
    func testCrashFreeRateAllGood() {
        var metrics = AnalyticsCollector.AggregateMetrics()
        metrics.totalSessions = 50
        metrics.crashFreeSessions = 50

        #expect(metrics.crashFreeRate == 1.0)
    }

    @Test("crashFreeRate is 0.0 when all sessions crash")
    func testCrashFreeRateAllCrashed() {
        var metrics = AnalyticsCollector.AggregateMetrics()
        metrics.totalSessions = 10
        metrics.crashFreeSessions = 0

        #expect(metrics.crashFreeRate == 0.0)
    }

    @Test("Zero sessions returns safe defaults for all computed properties")
    func testZeroSessionsSafeDefaults() {
        let metrics = AnalyticsCollector.AggregateMetrics()

        // With 0 sessions/calls, computed properties should not divide by zero
        #expect(metrics.toolSuccessRate == 1.0)
        #expect(metrics.avgReactIterations == 0)
        #expect(metrics.avgContextUtilization == 0)
        #expect(metrics.crashFreeRate == 1.0)
    }

    @Test("avgContextUtilization computation")
    func testAvgContextUtilizationComputation() {
        var metrics = AnalyticsCollector.AggregateMetrics()
        metrics.totalSessions = 4
        metrics.totalContextUsageSum = 3.0

        // Average = 3.0 / 4 = 0.75
        #expect(metrics.avgContextUtilization == 0.75)
    }

    @Test("AggregateMetrics round-trips via Codable")
    func testAggregateMetricsCodable() throws {
        var original = AnalyticsCollector.AggregateMetrics()
        original.totalSessions = 42
        original.crashFreeSessions = 40
        original.totalToolCalls = 200
        original.totalToolFailures = 5
        original.totalReactIterations = 100
        original.totalContextUsageSum = 30.0

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AnalyticsCollector.AggregateMetrics.self, from: data)

        #expect(decoded.totalSessions == 42)
        #expect(decoded.crashFreeSessions == 40)
        #expect(decoded.totalToolCalls == 200)
        #expect(decoded.totalToolFailures == 5)
        #expect(decoded.totalReactIterations == 100)
        #expect(decoded.totalContextUsageSum == 30.0)
    }
}

// MARK: - Suite 6: Offline Manager Tests

@Suite("Offline Manager Tests")
struct OfflineManagerTests {

    @Test("CachedToolResult detects staleness when timestamp exceeds threshold")
    @MainActor
    func testCachedToolResultStaleness() {
        // Create a result cached well beyond the staleness threshold (1 hour)
        let staleDate = Date().addingTimeInterval(-(OfflineManager.stalenessThreshold + 60))
        let staleResult = OfflineManager.CachedToolResult(
            toolName: "weather",
            arguments: "{\"location\": \"SF\"}",
            result: "Sunny, 72F",
            cachedAt: staleDate
        )
        #expect(staleResult.isStale == true)

        // Create a result cached just now (should not be stale)
        let freshResult = OfflineManager.CachedToolResult(
            toolName: "weather",
            arguments: "{\"location\": \"SF\"}",
            result: "Sunny, 72F",
            cachedAt: Date()
        )
        #expect(freshResult.isStale == false)
    }

    @Test("CachedToolResult is not stale within threshold")
    @MainActor
    func testCachedToolResultFreshWithinThreshold() {
        // 30 minutes ago — within the 1-hour threshold
        let recentDate = Date().addingTimeInterval(-1800)
        let result = OfflineManager.CachedToolResult(
            toolName: "calculator",
            arguments: "{}",
            result: "42",
            cachedAt: recentDate
        )
        #expect(result.isStale == false)
    }

    @Test("CachedToolResult ageDescription formatting")
    @MainActor
    func testCachedToolResultAgeDescription() {
        // Just now (< 60 seconds)
        let justNow = OfflineManager.CachedToolResult(
            toolName: "test",
            arguments: "",
            result: "",
            cachedAt: Date().addingTimeInterval(-10)
        )
        #expect(justNow.ageDescription == "just now")

        // 5 minutes ago
        let fiveMinAgo = OfflineManager.CachedToolResult(
            toolName: "test",
            arguments: "",
            result: "",
            cachedAt: Date().addingTimeInterval(-300)
        )
        #expect(fiveMinAgo.ageDescription == "5m ago")

        // 2 hours ago
        let twoHoursAgo = OfflineManager.CachedToolResult(
            toolName: "test",
            arguments: "",
            result: "",
            cachedAt: Date().addingTimeInterval(-7200)
        )
        #expect(twoHoursAgo.ageDescription == "2h ago")

        // 3 days ago
        let threeDaysAgo = OfflineManager.CachedToolResult(
            toolName: "test",
            arguments: "",
            result: "",
            cachedAt: Date().addingTimeInterval(-259200)
        )
        #expect(threeDaysAgo.ageDescription == "3d ago")
    }

    @Test("Caching and retrieving tool results via OfflineManager.shared")
    @MainActor
    func testCacheAndRetrieveToolResult() {
        let manager = OfflineManager.shared

        // Clear any existing cache to start fresh
        manager.clearCache()

        // Cache a result
        manager.cacheToolResult(
            name: "calculator",
            arguments: "{\"expression\": \"2+2\"}",
            result: "4"
        )

        // Retrieve with exact arguments match
        let specific = manager.getCachedResult(name: "calculator", arguments: "{\"expression\": \"2+2\"}")
        #expect(specific != nil)
        #expect(specific?.result == "4")
        #expect(specific?.toolName == "calculator")

        // Retrieve by tool name only (generic fallback)
        let generic = manager.getCachedResult(name: "calculator")
        #expect(generic != nil)
        #expect(generic?.result == "4")

        // Non-existent tool returns nil
        let missing = manager.getCachedResult(name: "nonexistent_tool")
        #expect(missing == nil)

        // Clean up
        manager.clearCache()
    }

    @Test("clearCache removes all cached results")
    @MainActor
    func testClearCache() {
        let manager = OfflineManager.shared
        manager.clearCache()

        manager.cacheToolResult(name: "tool_a", arguments: "{}", result: "result_a")
        manager.cacheToolResult(name: "tool_b", arguments: "{}", result: "result_b")

        // Both should exist
        #expect(manager.getCachedResult(name: "tool_a") != nil)
        #expect(manager.getCachedResult(name: "tool_b") != nil)

        // Clear and verify
        manager.clearCache()
        #expect(manager.getCachedResult(name: "tool_a") == nil)
        #expect(manager.getCachedResult(name: "tool_b") == nil)
    }

    @Test("CachedToolResult Codable round-trip")
    @MainActor
    func testCachedToolResultCodable() throws {
        let original = OfflineManager.CachedToolResult(
            toolName: "weather",
            arguments: "{\"location\": \"NYC\"}",
            result: "Cloudy, 55F",
            cachedAt: Date()
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(OfflineManager.CachedToolResult.self, from: data)

        #expect(decoded.toolName == original.toolName)
        #expect(decoded.arguments == original.arguments)
        #expect(decoded.result == original.result)
        // Timestamps may have minor floating-point differences, check within 1 second
        #expect(abs(decoded.cachedAt.timeIntervalSince(original.cachedAt)) < 1.0)
    }
}
