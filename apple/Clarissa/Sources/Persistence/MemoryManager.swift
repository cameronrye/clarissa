import Foundation
import os.log

private let logger = Logger(subsystem: "dev.rye.Clarissa", category: "MemoryManager")

/// Manages long-term memories for the agent
/// Syncs across devices via iCloud Key-Value Storage (NSUbiquitousKeyValueStore)
/// On macOS, also syncs with CLI at ~/.clarissa/memories.json for cross-app memory sharing
/// On iOS, uses Keychain as backup storage
public actor MemoryManager {
    public static let shared = MemoryManager()

    private var memories: [Memory] = []
    private var isLoaded = false

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

    /// Handle external iCloud changes
    private func handleICloudChange(reason: Int?, changedKeys: [String]) async {
        guard let changeReason = reason else { return }

        switch changeReason {
        case NSUbiquitousKeyValueStoreServerChange,
             NSUbiquitousKeyValueStoreInitialSyncChange:
            if changedKeys.contains(Self.iCloudMemoriesKey) || changedKeys.isEmpty {
                logger.info("iCloud memories changed externally, reloading")
                await reload()
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
    func add(_ content: String) async {
        await ensureLoaded()

        // Sanitize content before storing
        let sanitizedContent = sanitize(content)
        guard !sanitizedContent.isEmpty else {
            logger.info("Skipping empty memory after sanitization")
            return
        }

        // Check for duplicate content
        let normalizedContent = sanitizedContent.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if memories.contains(where: { $0.content.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == normalizedContent }) {
            logger.info("Skipping duplicate memory")
            return
        }

        // Auto-tag memory with topics using ContentTagger (iOS 26+)
        var topics: [String]? = nil
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            topics = await extractTopicsForMemory(sanitizedContent)
        }
        #endif

        let memory = Memory(content: sanitizedContent, topics: topics)
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

    /// Get memories formatted for the system prompt
    /// Includes topic tags when available for better context
    func getForPrompt() async -> String? {
        await ensureLoaded()

        guard !memories.isEmpty else {
            logger.debug("getForPrompt: No memories to include")
            return nil
        }

        // Take most recent memories first
        let recentMemories = memories.suffix(20)
        let memoryList = recentMemories.map { memory -> String in
            if let topics = memory.topics, !topics.isEmpty {
                let topicStr = topics.joined(separator: ", ")
                return "- \(memory.content) [topics: \(topicStr)]"
            }
            return "- \(memory.content)"
        }.joined(separator: "\n")

        logger.info("getForPrompt: Including \(recentMemories.count) memories in system prompt")

        return """
        ## Saved Facts About This User

        \(memoryList)

        IMPORTANT: When the user asks about their name, preferences, or anything in the saved facts above, respond using this information directly. For example:
        - "Say my name" or "What's my name?" -> Answer with their name from saved facts
        - "What do you know about me?" -> List the saved facts
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

    /// Merge memories from multiple sources, deduplicating by content
    private func mergeMemories(_ sources: [Memory]...) -> [Memory] {
        var seen = Set<String>()
        var merged: [Memory] = []

        // Flatten and sort by date (newest first for deduplication priority)
        let all = sources.flatMap { $0 }.sorted { $0.createdAt > $1.createdAt }

        for memory in all {
            let normalized = memory.content.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if !seen.contains(normalized) {
                seen.insert(normalized)
                merged.append(memory)
            }
        }

        // Sort by date (oldest first) and limit to max
        merged.sort { $0.createdAt < $1.createdAt }
        if merged.count > Self.maxMemories {
            merged = Array(merged.suffix(Self.maxMemories))
        }

        return merged
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
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(memories)

            guard let jsonString = String(data: data, encoding: .utf8) else {
                logger.error("Failed to encode memories to string")
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
        } catch {
            logger.error("Failed to save memories to Keychain: \(error.localizedDescription)")
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

/// A single memory entry
struct Memory: Identifiable, Codable {
    let id: UUID
    let content: String
    let createdAt: Date

    /// Optional topics extracted by ContentTagger (iOS 26+)
    var topics: [String]?

    init(id: UUID = UUID(), content: String, createdAt: Date = Date(), topics: [String]? = nil) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
        self.topics = topics
    }
}

