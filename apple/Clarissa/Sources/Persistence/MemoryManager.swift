import Foundation
import os.log

private let logger = Logger(subsystem: "dev.rye.Clarissa", category: "MemoryManager")

/// Manages long-term memories for the agent
/// Memories are stored securely in the Keychain to protect user data
actor MemoryManager {
    static let shared = MemoryManager()

    private var memories: [Memory] = []
    private var isLoaded = false

    /// Keychain storage (injectable for testing)
    private let keychain: KeychainStorage

    /// Keychain key for storing memories
    private static let memoriesKeychainKey = "clarissa_memories"

    /// Legacy file URL for migration (can be removed after a few versions)
    private let legacyFileURL: URL

    /// Maximum number of memories to store
    static let maxMemories = 100

    private init() {
        self.keychain = KeychainManager.shared
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.legacyFileURL = documentsPath.appendingPathComponent("clarissa_memories.json")
    }

    /// Creates a MemoryManager with a custom keychain storage (for testing)
    init(keychain: KeychainStorage) {
        self.keychain = keychain
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.legacyFileURL = documentsPath.appendingPathComponent("clarissa_memories.json")
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

        guard !memories.isEmpty else { return nil }

        // Take most recent memories first
        let recentMemories = memories.suffix(20)
        let memoryList = recentMemories.map { "- \($0.content)" }.joined(separator: "\n")

        return """
        ## Your Memories

        You have remembered the following from previous conversations:
        \(memoryList)

        Use these memories to provide more personalized and contextual responses.
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

    private func load() async {
        // First, try to load from Keychain (secure storage)
        if let memoriesJson = keychain.get(key: Self.memoriesKeychainKey),
           let data = memoriesJson.data(using: .utf8) {
            do {
                memories = try JSONDecoder().decode([Memory].self, from: data)
                isLoaded = true
                logger.info("Loaded \(self.memories.count) memories from Keychain")
                return
            } catch {
                logger.error("Failed to decode memories from Keychain: \(error.localizedDescription)")
            }
        }

        // Fall back to legacy file storage and migrate if found
        await migrateFromLegacyStorage()
        isLoaded = true
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

            try keychain.set(jsonString, forKey: Self.memoriesKeychainKey)
            logger.debug("Saved \(self.memories.count) memories to Keychain")
        } catch {
            logger.error("Failed to save memories to Keychain: \(error.localizedDescription)")
        }
    }
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

