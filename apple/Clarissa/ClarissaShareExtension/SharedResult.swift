import Foundation

// MARK: - Shared Constants (duplicated for extension target isolation)
// IMPORTANT: These values MUST match exactly:
//   appGroupIdentifier → ClarissaAppGroup.identifier in Sources/Widgets/WidgetData.swift
//   sharedResultsKey   → ClarissaConstants.sharedResultsKey in Sources/Constants.swift
// If you change one, you MUST change the other or inter-process communication will silently fail.

private let appGroupIdentifier = "group.dev.rye.clarissa"
private let sharedResultsKey = "clarissa_shared_results"

// MARK: - Shared Result Model

/// A result from the Share Extension processing
/// Stored in App Group UserDefaults for the main app to pick up
public struct SharedResult: Codable, Identifiable, Sendable {
    public let id: UUID
    public let type: SharedResultType
    public let originalContent: String
    public let analysis: String
    public let createdAt: Date
    /// Optional tool chain ID to trigger when this result is processed
    public let chainId: String?

    public init(type: SharedResultType, originalContent: String, analysis: String, chainId: String? = nil) {
        self.id = UUID()
        self.type = type
        self.originalContent = originalContent
        self.analysis = analysis
        self.createdAt = Date()
        self.chainId = chainId
    }
}

/// The type of content that was shared
public enum SharedResultType: String, Codable, Sendable {
    case text
    case url
    case image
}

// MARK: - Shared Result Store

/// Reads and writes SharedResults to the App Group UserDefaults
public enum SharedResultStore {
    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    /// Save a shared result for the main app to pick up
    public static func save(_ result: SharedResult) {
        guard let defaults = sharedDefaults else { return }

        var existing = load()
        existing.append(result)

        // Keep only the 5 most recent
        if existing.count > 5 {
            existing = Array(existing.suffix(5))
        }

        if let encoded = try? JSONEncoder().encode(existing) {
            defaults.set(encoded, forKey: sharedResultsKey)
        }
    }

    /// Load all pending shared results
    public static func load() -> [SharedResult] {
        guard let defaults = sharedDefaults,
              let data = defaults.data(forKey: sharedResultsKey),
              let results = try? JSONDecoder().decode([SharedResult].self, from: data)
        else { return [] }
        return results
    }

    /// Clear all shared results (called after main app picks them up)
    public static func clear() {
        sharedDefaults?.removeObject(forKey: sharedResultsKey)
    }
}
