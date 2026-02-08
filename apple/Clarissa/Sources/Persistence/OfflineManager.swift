import Foundation
import Network
import os.log

/// Monitors network connectivity and provides cached tool results for offline fallback.
/// When offline, tools that previously succeeded can return their last-known result
/// with a staleness indicator so the user still gets useful (if dated) information.
@MainActor
final class OfflineManager: ObservableObject {
    static let shared = OfflineManager()

    private static let logger = Logger(subsystem: "dev.rye.Clarissa", category: "Offline")
    private static let cacheKey = "clarissa_tool_cache"

    /// Whether the device is currently offline
    @Published private(set) var isOffline: Bool = false

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "dev.rye.clarissa.network-monitor")

    /// Staleness threshold — cached results older than this are marked as stale
    nonisolated static let stalenessThreshold: TimeInterval = 3600 // 1 hour

    // MARK: - Cached Tool Results

    struct CachedToolResult: Codable {
        let toolName: String
        let arguments: String
        let result: String
        let cachedAt: Date

        var isStale: Bool {
            Date().timeIntervalSince(cachedAt) > OfflineManager.stalenessThreshold
        }

        var ageDescription: String {
            let interval = Date().timeIntervalSince(cachedAt)
            if interval < 60 { return "just now" }
            if interval < 3600 { return "\(Int(interval / 60))m ago" }
            if interval < 86400 { return "\(Int(interval / 3600))h ago" }
            return "\(Int(interval / 86400))d ago"
        }
    }

    private var cache: [String: CachedToolResult] = [:]
    private var isCacheLoaded = false

    private init() {
        startMonitoring()
    }

    // MARK: - Network Monitoring

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                let wasOffline = self?.isOffline ?? false
                self?.isOffline = (path.status != .satisfied)

                if wasOffline && path.status == .satisfied {
                    Self.logger.info("Network restored")
                } else if !wasOffline && path.status != .satisfied {
                    Self.logger.info("Network lost — offline mode active")
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    // MARK: - Cache Operations

    /// Maximum cache entries to prevent unbounded growth
    private static let maxCacheEntries = 200

    /// Cache a successful tool result for offline fallback
    func cacheToolResult(name: String, arguments: String, result: String) {
        ensureCacheLoaded()
        let cached = CachedToolResult(
            toolName: name,
            arguments: arguments,
            result: result,
            cachedAt: Date()
        )
        // Key by tool name + arguments for specific cache hits
        let key = "\(name):\(arguments)"
        cache[key] = cached
        // Also cache by just tool name for generic fallback
        cache[name] = cached

        // Evict oldest entries if cache exceeds max size
        if cache.count > Self.maxCacheEntries {
            let sorted = cache.sorted { $0.value.cachedAt < $1.value.cachedAt }
            let toRemove = cache.count - Self.maxCacheEntries
            for (key, _) in sorted.prefix(toRemove) {
                cache.removeValue(forKey: key)
            }
        }

        saveCache()
    }

    /// Get a cached result for a tool, optionally matching specific arguments
    func getCachedResult(name: String, arguments: String? = nil) -> CachedToolResult? {
        ensureCacheLoaded()
        if let args = arguments, let specific = cache["\(name):\(args)"] {
            return specific
        }
        return cache[name]
    }

    /// Clear all cached results
    func clearCache() {
        cache.removeAll()
        saveCache()
    }

    // MARK: - Persistence

    private func ensureCacheLoaded() {
        guard !isCacheLoaded else { return }
        loadCache()
        isCacheLoaded = true
    }

    private func loadCache() {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey) else { return }
        do {
            cache = try JSONDecoder().decode([String: CachedToolResult].self, from: data)
            Self.logger.debug("Loaded \(self.cache.count) cached tool results")
        } catch {
            Self.logger.warning("Failed to load tool cache: \(error.localizedDescription)")
        }
    }

    private func saveCache() {
        do {
            let data = try JSONEncoder().encode(cache)
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        } catch {
            Self.logger.warning("Failed to save tool cache: \(error.localizedDescription)")
        }
    }
}
