import Foundation
import os.log

private let logger = Logger(subsystem: "dev.rye.Clarissa", category: "MemoryManager")

/// Sync status for iCloud memory synchronization
public enum MemorySyncStatus: Sendable {
    case idle
    case syncing
    case synced
    case error(String)
}

/// Manages long-term memories for the agent
/// Syncs across devices via iCloud Key-Value Storage (NSUbiquitousKeyValueStore)
/// On macOS, also syncs with CLI at ~/.clarissa/memories.json for cross-app memory sharing
/// On iOS, uses Keychain as backup storage
public actor MemoryManager {
    public static let shared = MemoryManager()

    private var memories: [Memory] = []
    private var isLoaded = false

    /// Current sync status for UI display
    private(set) var syncStatus: MemorySyncStatus = .idle

    /// Keychain storage (injectable for testing)
    private let keychain: KeychainStorage

    /// iCloud Key-Value Store for cross-device sync
    private let iCloudStore: NSUbiquitousKeyValueStore

    /// Keychain key for storing memories (backup storage)
    private static let memoriesKeychainKey = "clarissa_memories"

    /// iCloud key for storing memories
    private static let iCloudMemoriesKey = "clarissa_memories"

    /// Legacy file URL for migration (can be removed after a few versions)
    private let legacyFileURL: URL

    /// Shared CLI memory file path (~/.clarissa/memories.json)
    /// Used on macOS to sync memories with the CLI app
    private let sharedCLIMemoryURL: URL?

    /// Maximum number of memories to store
    static let maxMemories = 100

    /// Whether iCloud sync is enabled (can be disabled for testing)
    private let iCloudEnabled: Bool

    private init() {
        self.keychain = KeychainManager.shared
        self.iCloudStore = NSUbiquitousKeyValueStore.default
        self.iCloudEnabled = true
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.legacyFileURL = documentsPath.appendingPathComponent("clarissa_memories.json")

        #if os(macOS)
        // On macOS, use shared CLI directory for cross-app memory sync
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let clarissaDir = homeDir.appendingPathComponent(".clarissa")
        self.sharedCLIMemoryURL = clarissaDir.appendingPathComponent("memories.json")
        #else
        self.sharedCLIMemoryURL = nil
        #endif
    }

    /// Creates a MemoryManager with a custom keychain storage (for testing)
    init(keychain: KeychainStorage, iCloudEnabled: Bool = false) {
        self.keychain = keychain
        self.iCloudStore = NSUbiquitousKeyValueStore.default
        self.iCloudEnabled = iCloudEnabled
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.legacyFileURL = documentsPath.appendingPathComponent("clarissa_memories.json")
        self.sharedCLIMemoryURL = nil
    }

    /// Start observing iCloud changes - call this from app startup
    public nonisolated func startObservingICloudChanges() {
        let store = NSUbiquitousKeyValueStore.default

        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }

            // Extract values from notification before crossing actor boundary
            let userInfo = notification.userInfo
            let changeReason = userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            let changedKeys = userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []

            Task {
                await self.handleICloudChange(reason: changeReason, changedKeys: changedKeys)
            }
        }

        // Trigger initial sync
        store.synchronize()
        logger.info("Started observing iCloud Key-Value Store changes")
    }

    /// Handle external iCloud changes with conflict detection
    private func handleICloudChange(reason: Int?, changedKeys: [String]) async {
        guard let changeReason = reason else { return }

        switch changeReason {
        case NSUbiquitousKeyValueStoreServerChange,
             NSUbiquitousKeyValueStoreInitialSyncChange:
            if changedKeys.contains(Self.iCloudMemoriesKey) || changedKeys.isEmpty {
                logger.info("iCloud memories changed externally, merging")
                // Load remote memories and merge with local
                let remoteMemories = loadFromICloud()
                let localMemories = self.memories
                let merged = mergeMemories(localMemories, remoteMemories)
                let changed = merged.count != localMemories.count ||
                    zip(merged, localMemories).contains(where: { $0.id != $1.id || $0.content != $1.content })
                self.memories = merged
                if changed {
                    logger.info("Merged iCloud changes: \(localMemories.count) local + \(remoteMemories.count) remote -> \(merged.count) merged")
                    await save()
                }
            }
        case NSUbiquitousKeyValueStoreQuotaViolationChange:
            logger.warning("iCloud Key-Value Store quota exceeded")
        case NSUbiquitousKeyValueStoreAccountChange:
            logger.info("iCloud account changed, reloading memories")
            await reload()
        default:
            break
        }
    }

    /// Ensure data is loaded before accessing
    private func ensureLoaded() async {
        if !isLoaded {
            await load()
        }
    }

    /// Sanitize memory content to prevent prompt injection
    /// Community insight: "Never interpolate untrusted user input into instructions"
    private func sanitize(_ content: String) -> String {
        var sanitized = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            // Remove potential instruction override attempts
            .replacingOccurrences(of: "SYSTEM:", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "INSTRUCTIONS:", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "IGNORE", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "OVERRIDE", with: "", options: .caseInsensitive)
            // Remove markdown headers that could look like new sections
            .replacingOccurrences(of: "##", with: "")
            .replacingOccurrences(of: "#", with: "")

        // Limit length to prevent context overflow
        if sanitized.count > 500 {
            sanitized = String(sanitized.prefix(500)) + "..."
        }

        return sanitized
    }

    /// Add a new memory
    /// Automatically tags memories with topics using ContentTagger on iOS 26+
    /// Uses both exact-match and semantic deduplication
    func add(_ content: String) async {
        await ensureLoaded()

        // Sanitize content before storing
        let sanitizedContent = sanitize(content)
        guard !sanitizedContent.isEmpty else {
            logger.info("Skipping empty memory after sanitization")
            return
        }

        // Check for exact duplicate content
        let normalizedContent = sanitizedContent.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if memories.contains(where: { $0.content.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == normalizedContent }) {
            logger.info("Skipping duplicate memory (exact match)")
            return
        }

        // Check for semantic duplicates (substring or high similarity)
        if memories.contains(where: { areSemanticallyDuplicate($0.content, sanitizedContent) }) {
            logger.info("Skipping duplicate memory (semantic match)")
            return
        }

        // Auto-tag memory with topics using ContentTagger (iOS 26+)
        var topics: [String]? = nil
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            topics = await extractTopicsForMemory(sanitizedContent)
        }
        #endif

        let (category, temporalType) = detectCategory(for: sanitizedContent)
        let memory = Memory(content: sanitizedContent, topics: topics, category: category, temporalType: temporalType)
        memories.append(memory)

        // Trim old memories if needed
        if memories.count > Self.maxMemories {
            let toRemove = memories.count - Self.maxMemories
            memories.removeFirst(toRemove)
            logger.info("Trimmed \(toRemove) old memories")
        }

        await save()
    }

    /// Extract topics from memory content using ContentTagger
    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private func extractTopicsForMemory(_ content: String) async -> [String]? {
        do {
            let topics = try await MainActor.run {
                Task {
                    try await ContentTagger.shared.extractTopics(from: content)
                }
            }.value
            logger.debug("Tagged memory with topics: \(topics)")
            return topics.isEmpty ? nil : topics
        } catch {
            logger.warning("Failed to tag memory: \(error.localizedDescription)")
            return nil
        }
    }
    #endif

    /// Get all memories
    func getAll() async -> [Memory] {
        await ensureLoaded()
        return memories
    }

    /// Get the current sync status
    public func getSyncStatus() -> MemorySyncStatus {
        return syncStatus
    }

    // MARK: - Category Detection

    /// Heuristic category detection based on keyword patterns
    private func detectCategory(for content: String) -> (MemoryCategory, MemoryTemporalType) {
        let lower = content.lowercased()

        let preferencePatterns = ["prefer", "like", "love", "hate", "favorite", "favourite",
                                   "rather", "enjoy", "dislike", "don't like"]
        if preferencePatterns.contains(where: { lower.contains($0) }) {
            return (.preference, .permanent)
        }

        let routinePatterns = ["every", "always", "usually", "monday", "tuesday", "wednesday",
                                "thursday", "friday", "saturday", "sunday", "weekly", "daily",
                                "morning", "evening", "routine"]
        if routinePatterns.contains(where: { lower.contains($0) }) {
            return (.routine, .recurring)
        }

        let relationshipPatterns = ["wife", "husband", "partner", "daughter", "son", "mother",
                                     "father", "sister", "brother", "friend", "boss", "colleague",
                                     "'s name is", "married to"]
        if relationshipPatterns.contains(where: { lower.contains($0) }) {
            return (.relationship, .permanent)
        }

        let oneTimePatterns = ["appointment", "next week", "this weekend", "tomorrow", "deadline"]
        if oneTimePatterns.contains(where: { lower.contains($0) }) {
            return (.fact, .oneTime)
        }

        return (.fact, .permanent)
    }

    // MARK: - Confidence Tracking

    /// Counter for debouncing confidence saves
    private var confidenceUpdateCounter = 0

    /// Apply confidence decay/boost to all memories based on which were accessed
    private func updateConfidenceScores(accessedIds: Set<UUID>) {
        let now = Date()
        for i in memories.indices {
            if accessedIds.contains(memories[i].id) {
                memories[i].confidence = min(1.0, (memories[i].confidence ?? 0.5) + 0.05)
                memories[i].lastAccessedAt = now
                memories[i].accessCount = (memories[i].accessCount ?? 0) + 1
                memories[i].modifiedAt = now
                memories[i].deviceId = DeviceIdentifier.current
            } else {
                let current = memories[i].confidence ?? 0.5
                memories[i].confidence = max(0.1, current - 0.01)
            }
        }

        // Debounce saves — only save every 5th confidence update
        confidenceUpdateCounter += 1
        if confidenceUpdateCounter >= 5 {
            confidenceUpdateCounter = 0
            Task { await save() }
        }
    }

    // MARK: - Relationships

    /// Link two memories as related (bidirectional)
    func linkMemories(_ id1: UUID, _ id2: UUID) async {
        await ensureLoaded()
        let now = Date()
        if let i1 = memories.firstIndex(where: { $0.id == id1 }) {
            var rels = memories[i1].relationships ?? []
            if !rels.contains(id2) { rels.append(id2) }
            memories[i1].relationships = rels
            memories[i1].modifiedAt = now
            memories[i1].deviceId = DeviceIdentifier.current
        }
        if let i2 = memories.firstIndex(where: { $0.id == id2 }) {
            var rels = memories[i2].relationships ?? []
            if !rels.contains(id1) { rels.append(id1) }
            memories[i2].relationships = rels
            memories[i2].modifiedAt = now
            memories[i2].deviceId = DeviceIdentifier.current
        }
        await save()
    }

    /// Suggest relationships between memories with significant topic overlap
    func suggestRelationships() async -> [(Memory, Memory)] {
        await ensureLoaded()
        var suggestions: [(Memory, Memory)] = []

        for i in 0..<memories.count {
            for j in (i+1)..<memories.count {
                let mem1 = memories[i]
                let mem2 = memories[j]
                if let rels = mem1.relationships, rels.contains(mem2.id) { continue }
                if let t1 = mem1.topics, !t1.isEmpty,
                   let t2 = mem2.topics, !t2.isEmpty {
                    let overlap = Set(t1).intersection(Set(t2))
                    let ratio = Double(overlap.count) / Double(min(t1.count, t2.count))
                    if ratio >= ClarissaConstants.memoryTopicOverlapThreshold {
                        suggestions.append((mem1, mem2))
                    }
                }
            }
        }
        return suggestions
    }

    /// Get memories formatted for the system prompt
    /// Includes topic tags when available for better context
    /// Optimized for token efficiency while maintaining clarity
    func getForPrompt() async -> String? {
        await ensureLoaded()

        guard !memories.isEmpty else {
            logger.debug("getForPrompt: No memories to include")
            return nil
        }

        // Sort by confidence (descending), then take top 20
        let ranked = memories
            .sorted { ($0.confidence ?? 0.5) > ($1.confidence ?? 0.5) }
            .prefix(20)

        let accessedIds = Set(ranked.map(\.id))
        updateConfidenceScores(accessedIds: accessedIds)

        let memoryList = ranked.map { memory -> String in
            if let topics = memory.topics, !topics.isEmpty {
                let topicStr = topics.joined(separator: ", ")
                return "- \(memory.content) [\(topicStr)]"
            }
            return "- \(memory.content)"
        }.joined(separator: "\n")

        logger.info("getForPrompt: Including \(ranked.count) memories in system prompt")

        // Concise format - the system prompt already instructs to use saved facts
        return """
        USER FACTS:
        \(memoryList)
        """
    }

    /// Clear all memories
    func clear() async {
        await ensureLoaded()
        memories.removeAll()
        await save()
    }

    /// Remove a specific memory
    func remove(id: UUID) async {
        await ensureLoaded()
        memories.removeAll { $0.id == id }
        await save()
    }

    // MARK: - Relevance Ranking

    /// Get memories ranked by relevance to the current conversation topics
    /// Returns the most relevant memories formatted for the system prompt
    func getRelevantForConversation(topics conversationTopics: [String]) async -> String? {
        await ensureLoaded()

        guard !memories.isEmpty, !conversationTopics.isEmpty else {
            return await getForPrompt()
        }

        let conversationTopicSet = Set(conversationTopics.map { $0.lowercased() })

        // Multi-factor scoring
        var scored: [(memory: Memory, score: Double)] = []
        for memory in memories {
            var score: Double = 0.0

            // Topic overlap (40%)
            if let memTopics = memory.topics, !memTopics.isEmpty {
                let memTopicSet = Set(memTopics.map { $0.lowercased() })
                let overlap = conversationTopicSet.intersection(memTopicSet)
                score += 0.4 * (Double(overlap.count) / Double(conversationTopicSet.count))
            } else {
                score += 0.04
            }

            // Confidence (30%)
            score += 0.3 * Double(memory.confidence ?? 0.5)

            // Recency (20%) — decay over 90 days
            let daysSinceAccess = Date().timeIntervalSince(memory.lastAccessedAt ?? memory.createdAt) / 86400
            let recencyScore = max(0, 1.0 - (daysSinceAccess / 90.0))
            score += 0.2 * recencyScore

            // Category bonus (10%)
            switch memory.category {
            case .preference: score += 0.1
            case .routine:    score += 0.08
            case .relationship: score += 0.06
            default: score += 0.02
            }

            scored.append((memory, score))
        }

        // Sort by relevance (highest first), take top 10
        let topMemories = scored
            .sorted { $0.score > $1.score }
            .prefix(10)
            .map { $0.memory }

        // Track confidence
        let accessedIds = Set(topMemories.map(\.id))
        updateConfidenceScores(accessedIds: accessedIds)

        guard !topMemories.isEmpty else { return nil }

        let memoryList = topMemories.map { memory -> String in
            if let topics = memory.topics, !topics.isEmpty {
                let topicStr = topics.joined(separator: ", ")
                return "- \(memory.content) [\(topicStr)]"
            }
            return "- \(memory.content)"
        }.joined(separator: "\n")

        logger.info("getRelevantForConversation: Including \(topMemories.count) relevant memories")

        return """
        USER FACTS:
        \(memoryList)
        """
    }

    // MARK: - Staleness Detection

    /// Get memories older than the stale threshold for user review
    func getStaleMemories() async -> [Memory] {
        await ensureLoaded()

        guard let threshold = Calendar.current.date(
            byAdding: .day,
            value: -ClarissaConstants.memoryStaleThresholdDays,
            to: Date()
        ) else { return [] }

        return memories.filter { $0.createdAt < threshold }
    }

    /// Count of stale memories for badge display
    func staleMemoryCount() async -> Int {
        let stale = await getStaleMemories()
        return stale.count
    }

    // MARK: - Duplicate Management

    /// Run semantic deduplication across all memories
    func mergeDuplicates() async {
        await ensureLoaded()
        let before = memories.count
        memories = deduplicateMemories(memories)
        let removed = before - memories.count
        if removed > 0 {
            logger.info("Merged \(removed) duplicate memories")
            await save()
        }
    }

    /// Force reload memories from all sources (useful for CLI sync)
    public func reload() async {
        isLoaded = false
        await load()
        logger.info("Reloaded memories, now have \(self.memories.count) memories")
    }

    private func load() async {
        var keychainMemories: [Memory] = []
        var iCloudMemories: [Memory] = []
        var cliMemories: [Memory] = []

        // Load from iCloud Key-Value Store (cross-device sync)
        if iCloudEnabled {
            iCloudMemories = loadFromICloud()
        }

        // Load from Keychain (local backup storage)
        if let memoriesJson = keychain.get(key: Self.memoriesKeychainKey),
           let data = memoriesJson.data(using: .utf8) {
            do {
                keychainMemories = try JSONDecoder().decode([Memory].self, from: data)
                logger.info("Loaded \(keychainMemories.count) memories from Keychain")
            } catch {
                logger.error("Failed to decode memories from Keychain: \(error.localizedDescription)")
            }
        }

        // On macOS, also load from shared CLI memory file and merge
        #if os(macOS)
        cliMemories = await loadFromSharedCLIFile()
        #endif

        // Merge memories from all sources, preferring newer entries for duplicates
        // Priority: iCloud (cross-device) > Keychain (local) > CLI (macOS only)
        memories = mergeMemories(iCloudMemories, keychainMemories, cliMemories)

        // Fall back to legacy file storage and migrate if found
        if memories.isEmpty {
            await migrateFromLegacyStorage()
        }

        isLoaded = true

        // Sync merged memories back to all stores
        let hasAnyMemories = !iCloudMemories.isEmpty || !keychainMemories.isEmpty || !cliMemories.isEmpty
        if hasAnyMemories {
            await save()
        }
    }

    /// Load memories from iCloud Key-Value Store
    private func loadFromICloud() -> [Memory] {
        guard let memoriesJson = iCloudStore.string(forKey: Self.iCloudMemoriesKey),
              let data = memoriesJson.data(using: .utf8) else {
            logger.debug("No memories found in iCloud")
            return []
        }

        do {
            let memories = try JSONDecoder().decode([Memory].self, from: data)
            logger.info("Loaded \(memories.count) memories from iCloud")
            return memories
        } catch {
            logger.error("Failed to decode memories from iCloud: \(error.localizedDescription)")
            return []
        }
    }

    /// Load memories from the shared CLI file (~/.clarissa/memories.json)
    #if os(macOS)
    private func loadFromSharedCLIFile() async -> [Memory] {
        guard let sharedURL = sharedCLIMemoryURL,
              FileManager.default.fileExists(atPath: sharedURL.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: sharedURL)
            let cliMemories = try JSONDecoder().decode([CLIMemory].self, from: data)
            logger.info("Loaded \(cliMemories.count) memories from CLI file")

            // Convert CLI memory format to native format
            return cliMemories.map { cliMem in
                Memory(
                    id: UUID(), // Generate new UUID since CLI uses string IDs
                    content: cliMem.content,
                    createdAt: ISO8601DateFormatter().date(from: cliMem.createdAt) ?? Date()
                )
            }
        } catch {
            logger.error("Failed to load CLI memories: \(error.localizedDescription)")
            return []
        }
    }
    #endif

    /// Merge memories from multiple sources with timestamp-based conflict resolution.
    /// For memories with the same ID edited on different devices, latest-edit-wins.
    /// Unique memories (different IDs) are unioned automatically.
    private func mergeMemories(_ sources: [Memory]...) -> [Memory] {
        let all = sources.flatMap { $0 }

        // Group by ID to detect same-memory conflicts
        var byId: [UUID: [Memory]] = [:]
        for memory in all {
            byId[memory.id, default: []].append(memory)
        }

        var resolved: [Memory] = []
        for (id, versions) in byId {
            if versions.count == 1 {
                resolved.append(versions[0])
            } else {
                // Multiple versions of same memory — latest modifiedAt wins
                let winner = versions.max(by: {
                    ($0.modifiedAt ?? $0.createdAt) < ($1.modifiedAt ?? $1.createdAt)
                }) ?? versions[0]

                // Detect near-simultaneous edits from different devices (within 5 min)
                let sorted = versions.sorted { ($0.modifiedAt ?? $0.createdAt) > ($1.modifiedAt ?? $1.createdAt) }
                if sorted.count >= 2,
                   let t1 = sorted[0].modifiedAt ?? Optional(sorted[0].createdAt),
                   let t2 = sorted[1].modifiedAt ?? Optional(sorted[1].createdAt),
                   abs(t1.timeIntervalSince(t2)) < 300, // 5 minutes
                   sorted[0].deviceId != sorted[1].deviceId,
                   sorted[0].content != sorted[1].content {
                    logger.warning("Conflict detected for memory \(id): edited on two devices within 5 minutes. Using latest edit.")
                }

                resolved.append(winner)
            }
        }

        // Sort by date (newest first) for deduplication priority, then deduplicate
        resolved.sort { $0.createdAt > $1.createdAt }
        return deduplicateMemories(resolved)
    }

    /// Deduplicate memories using exact match and semantic similarity
    private func deduplicateMemories(_ input: [Memory]) -> [Memory] {
        var seen = Set<String>()
        var deduplicated: [Memory] = []

        for memory in input {
            let normalized = memory.content.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

            // Exact match dedup
            if seen.contains(normalized) {
                continue
            }

            // Semantic dedup: check topic overlap + content similarity
            let hasSemantic = deduplicated.contains { existing in
                // Check topic overlap first (cheap)
                if let memTopics = memory.topics, !memTopics.isEmpty,
                   let existingTopics = existing.topics, !existingTopics.isEmpty {
                    let overlap = Set(memTopics).intersection(Set(existingTopics))
                    let overlapRatio = Double(overlap.count) / Double(min(memTopics.count, existingTopics.count))
                    if overlapRatio >= ClarissaConstants.memoryTopicOverlapThreshold {
                        return areSemanticallyDuplicate(memory.content, existing.content)
                    }
                }
                // If no topics, still check content similarity
                return areSemanticallyDuplicate(memory.content, existing.content)
            }

            if hasSemantic {
                continue
            }

            seen.insert(normalized)
            deduplicated.append(memory)
        }

        // Sort by date (oldest first) and limit to max
        deduplicated.sort { $0.createdAt < $1.createdAt }
        if deduplicated.count > Self.maxMemories {
            deduplicated = Array(deduplicated.suffix(Self.maxMemories))
        }

        return deduplicated
    }

    /// Check if two memory contents are semantically duplicate
    private func areSemanticallyDuplicate(_ content1: String, _ content2: String) -> Bool {
        let lower1 = content1.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let lower2 = content2.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Substring check: one contains the other
        if lower1.contains(lower2) || lower2.contains(lower1) {
            return true
        }

        // Skip Levenshtein for very different length strings (can't be similar)
        let lenRatio = Double(min(lower1.count, lower2.count)) / Double(max(lower1.count, lower2.count))
        if lenRatio < 0.5 {
            return false
        }

        // Levenshtein distance for content similarity
        let distance = levenshteinDistance(lower1, lower2)
        let maxLen = max(lower1.count, lower2.count)
        guard maxLen > 0 else { return true }
        let similarity = 1.0 - (Double(distance) / Double(maxLen))

        return similarity >= ClarissaConstants.memorySimilarityThreshold
    }

    /// Levenshtein edit distance between two strings
    private func levenshteinDistance(_ str1: String, _ str2: String) -> Int {
        let s1 = Array(str1)
        let s2 = Array(str2)
        let m = s1.count
        let n = s2.count

        if m == 0 { return n }
        if n == 0 { return m }

        var last = Array(0...n)
        var cur = [Int](repeating: 0, count: n + 1)

        for i in 1...m {
            cur[0] = i
            for j in 1...n {
                if s1[i - 1] == s2[j - 1] {
                    cur[j] = last[j - 1]
                } else {
                    cur[j] = min(last[j - 1], last[j], cur[j - 1]) + 1
                }
            }
            last = cur
        }

        return last[n]
    }

    /// Migrate memories from legacy file storage to Keychain
    private func migrateFromLegacyStorage() async {
        guard FileManager.default.fileExists(atPath: legacyFileURL.path) else {
            return
        }

        do {
            let data = try Data(contentsOf: legacyFileURL)
            memories = try JSONDecoder().decode([Memory].self, from: data)
            logger.info("Migrating \(self.memories.count) memories from file to Keychain")

            // Save to Keychain
            await save()

            // Remove legacy file after successful migration
            try FileManager.default.removeItem(at: legacyFileURL)
            logger.info("Removed legacy memories file after migration")
        } catch {
            logger.error("Failed to migrate memories from legacy storage: \(error.localizedDescription)")
        }
    }

    private func save() async {
        syncStatus = .syncing

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(memories)

            // Monitor payload size for iCloud KVS limits (64KB per key)
            let payloadKB = Double(data.count) / 1024.0
            if payloadKB > 60 {
                logger.error("Memory payload \(String(format: "%.1f", payloadKB))KB exceeds safe iCloud KVS limit (60KB). Risk of data loss!")
            } else if payloadKB > 50 {
                logger.warning("Memory payload \(String(format: "%.1f", payloadKB))KB approaching iCloud KVS limit (64KB per key). Consider pruning old memories.")
            }

            guard let jsonString = String(data: data, encoding: .utf8) else {
                logger.error("Failed to encode memories to string")
                syncStatus = .error("Failed to encode memories")
                return
            }

            // Save to iCloud Key-Value Store (cross-device sync)
            if iCloudEnabled {
                saveToICloud(jsonString)
            }

            // Save to Keychain (local backup storage)
            try keychain.set(jsonString, forKey: Self.memoriesKeychainKey)
            logger.debug("Saved \(self.memories.count) memories to Keychain")

            // On macOS, also save to shared CLI file
            #if os(macOS)
            await saveToSharedCLIFile()
            #endif

            syncStatus = .synced
        } catch {
            logger.error("Failed to save memories to Keychain: \(error.localizedDescription)")
            syncStatus = .error(error.localizedDescription)
        }
    }

    /// Save memories to iCloud Key-Value Store
    private func saveToICloud(_ jsonString: String) {
        iCloudStore.set(jsonString, forKey: Self.iCloudMemoriesKey)
        iCloudStore.synchronize()
        logger.debug("Saved \(self.memories.count) memories to iCloud")
    }

    /// Save memories to the shared CLI file (~/.clarissa/memories.json)
    #if os(macOS)
    private func saveToSharedCLIFile() async {
        guard let sharedURL = sharedCLIMemoryURL else { return }

        do {
            // Ensure ~/.clarissa directory exists
            let clarissaDir = sharedURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: clarissaDir.path) {
                try FileManager.default.createDirectory(at: clarissaDir, withIntermediateDirectories: true)
            }

            // Convert to CLI format
            let cliMemories = memories.map { mem in
                CLIMemory(
                    id: "mem_\(Int(mem.createdAt.timeIntervalSince1970))_\(mem.id.uuidString.prefix(4).lowercased())",
                    content: mem.content,
                    createdAt: ISO8601DateFormatter().string(from: mem.createdAt)
                )
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(cliMemories)
            try data.write(to: sharedURL, options: .atomic)
            logger.debug("Synced \(self.memories.count) memories to CLI file")
        } catch {
            logger.error("Failed to save to CLI memory file: \(error.localizedDescription)")
        }
    }
    #endif
}

// MARK: - CLI Memory Format

/// Memory format used by the CLI app (~/.clarissa/memories.json)
/// Matches the TypeScript interface in src/memory/index.ts
private struct CLIMemory: Codable {
    let id: String
    let content: String
    let createdAt: String
}

/// Category of memory content
enum MemoryCategory: String, Codable, CaseIterable {
    case fact
    case preference
    case routine
    case relationship
    case uncategorized
}

/// Temporal type of memory
enum MemoryTemporalType: String, Codable {
    case permanent
    case recurring
    case oneTime
}

/// A single memory entry
struct Memory: Identifiable, Codable {
    let id: UUID
    let content: String
    let createdAt: Date

    /// Optional topics extracted by ContentTagger (iOS 26+)
    var topics: [String]?

    // Memory intelligence fields (all Optional for backward-compatible Codable)
    var category: MemoryCategory?
    var temporalType: MemoryTemporalType?
    var confidence: Float?
    var relationships: [UUID]?
    var lastAccessedAt: Date?
    var accessCount: Int?

    // Conflict resolution fields (Optional for backward compat with existing data)
    /// Timestamp of the last modification (content edit, confidence update, etc.)
    var modifiedAt: Date?
    /// Identifier of the device that last modified this memory
    var deviceId: String?

    init(id: UUID = UUID(), content: String, createdAt: Date = Date(), topics: [String]? = nil,
         category: MemoryCategory? = nil, temporalType: MemoryTemporalType? = nil) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
        self.topics = topics
        self.category = category
        self.temporalType = temporalType
        self.confidence = 1.0
        self.lastAccessedAt = Date()
        self.accessCount = 0
        self.modifiedAt = Date()
        self.deviceId = DeviceIdentifier.current
    }
}

/// Stable per-device identifier for conflict resolution.
/// Uses identifierForVendor on iOS, a persisted UUID on macOS.
enum DeviceIdentifier {
    static let current: String = {
        #if os(iOS) || os(watchOS)
        if let vendorId = UIDevice.current.identifierForVendor?.uuidString {
            return vendorId
        }
        #endif
        // Fallback: persist a UUID in UserDefaults
        let key = "clarissa_device_id"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }()
}

