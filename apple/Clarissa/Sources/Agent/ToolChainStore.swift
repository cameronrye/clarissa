import Foundation

/// Persists user-created tool chains as JSON in the app's documents directory
actor ToolChainStore {
    static let shared = ToolChainStore()

    private let fileName = "custom_tool_chains.json"
    private var cachedChains: [ToolChain]?

    private var fileURL: URL {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            // Fallback to temporary directory if documents directory unavailable
            return FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        }
        return docs.appendingPathComponent(fileName)
    }

    func load() -> [ToolChain] {
        if let cached = cachedChains { return cached }
        let chains = loadFromDisk()
        cachedChains = chains
        return chains
    }

    /// Invalidate cache so next load() reads from disk
    func invalidateCache() {
        cachedChains = nil
    }

    private func loadFromDisk() -> [ToolChain] {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let chains = try? decoder.decode([ToolChain].self, from: data) else {
            return []
        }
        return chains
    }

    func save(_ chains: [ToolChain]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(chains)
        let url = fileURL
        let dir = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try data.write(to: url, options: .atomic)
        cachedChains = chains
    }

    func add(_ chain: ToolChain) throws {
        var chains = load()
        chains.append(chain)
        try save(chains)
    }

    func delete(id: String) throws {
        var chains = load()
        chains.removeAll { $0.id == id }
        try save(chains)
    }

    func update(_ chain: ToolChain) throws {
        var chains = load()
        guard let index = chains.firstIndex(where: { $0.id == chain.id }) else { return }
        chains[index] = chain
        try save(chains)
    }
}
