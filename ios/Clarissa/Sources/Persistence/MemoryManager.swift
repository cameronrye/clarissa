import Foundation
import os.log

private let logger = Logger(subsystem: "dev.rye.Clarissa", category: "MemoryManager")

/// Manages long-term memories for the agent
actor MemoryManager {
    static let shared = MemoryManager()

    private var memories: [Memory] = []
    private let fileURL: URL
    private var isLoaded = false

    /// Maximum number of memories to store
    static let maxMemories = 100

    private init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.fileURL = documentsPath.appendingPathComponent("clarissa_memories.json")
    }

    /// Ensure data is loaded before accessing
    private func ensureLoaded() async {
        if !isLoaded {
            await load()
        }
    }

    /// Add a new memory
    func add(_ content: String) async {
        await ensureLoaded()

        // Check for duplicate content
        let normalizedContent = content.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if memories.contains(where: { $0.content.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == normalizedContent }) {
            logger.info("Skipping duplicate memory")
            return
        }

        let memory = Memory(content: content)
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
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            isLoaded = true
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            memories = try JSONDecoder().decode([Memory].self, from: data)
            isLoaded = true
            logger.info("Loaded \(self.memories.count) memories")
        } catch {
            logger.error("Failed to load memories: \(error.localizedDescription)")
            isLoaded = true
        }
    }

    private func save() async {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(memories)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to save memories: \(error.localizedDescription)")
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

