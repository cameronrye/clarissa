import Foundation
import os.log

private let logger = Logger(subsystem: "dev.rye.Clarissa", category: "MemoryManager")

/// Manages long-term memories for the agent
/// On macOS, syncs with CLI at ~/.clarissa/memories.json for cross-app memory sharing
/// On iOS, uses Keychain for secure storage
public actor MemoryManager {
    public static let shared = MemoryManager()

    private var memories: [Memory] = []
    private var isLoaded = false

    /// Keychain storage (injectable for testing)
    private let keychain: KeychainStorage

    /// Keychain key for storing memories
    private static let memoriesKeychainKey = "clarissa_memories"

    /// Legacy file URL for migration (can be removed after a few versions)
    private let legacyFileURL: URL

    /// Shared CLI memory file path (~/.clarissa/memories.json)
    /// Used on macOS to sync memories with the CLI app
    private let sharedCLIMemoryURL: URL?

    /// Maximum number of memories to store
    static let maxMemories = 100

    private init() {
        self.keychain = KeychainManager.shared
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
    init(keychain: KeychainStorage) {
        self.keychain = keychain
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.legacyFileURL = documentsPath.appendingPathComponent("clarissa_memories.json")
        self.sharedCLIMemoryURL = nil
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

        let memory = Memory(content: sanitizedContent)
        memories.append(memory)

        // Trim old memories if needed
        if memories.count > Self.maxMemories {
            let toRemove = memories.count - Self.maxMemories
            memories.removeFirst(toRemove)
            logger.info("Trimmed \(toRemove) old memories")
        }

        await save()
    }

    /// Get all memories
    func getAll() async -> [Memory] {
        await ensureLoaded()
        return memories
    }

    /// Get memories formatted for the system prompt
    func getForPrompt() async -> String? {
        await ensureLoaded()

        guard !memories.isEmpty else {
            logger.debug("getForPrompt: No memories to include")
            return nil
        }

        // Take most recent memories first
        let recentMemories = memories.suffix(20)
        let memoryList = recentMemories.map { "- \($0.content)" }.joined(separator: "\n")

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
        var cliMemories: [Memory] = []

        // Load from Keychain (iOS primary storage, macOS secondary)
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

        // Merge memories from both sources, preferring newer entries for duplicates
        memories = mergeMemories(keychainMemories, cliMemories)

        // Fall back to legacy file storage and migrate if found
        if memories.isEmpty {
            await migrateFromLegacyStorage()
        }

        isLoaded = true

        // On macOS, sync merged memories back to both stores
        #if os(macOS)
        if !cliMemories.isEmpty || !keychainMemories.isEmpty {
            await save()
        }
        #endif
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

            // Save to Keychain (primary storage on iOS, backup on macOS)
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

    init(id: UUID = UUID(), content: String, createdAt: Date = Date()) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
    }
}

