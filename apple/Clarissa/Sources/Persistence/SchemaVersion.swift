import Foundation
import os.log

/// Schema version for the persistence layer.
/// Used to detect and migrate data when fields are added, renamed, or restructured.
enum SchemaVersion: Int, Codable, Comparable, Sendable {
    /// Pre-versioning data (v2.0 and earlier). No schemaVersion field present.
    case v1 = 1
    /// v2.1: Adds pin, favorite, summary, manualTags to Session/Message; analytics fields.
    case v2 = 2
    /// v2.2: Adds chainId to SharedResult; tool chain and scheduled check-in persistence.
    case v3 = 3

    /// The current schema version. All new saves use this.
    static let current: SchemaVersion = .v3

    static func < (lhs: SchemaVersion, rhs: SchemaVersion) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Lightweight migration pipeline for evolving persisted data.
///
/// Each migration transforms raw JSON `Data` from one version to the next.
/// Migrations run sequentially: v1→v2, v2→v3, etc.
enum SchemaMigrator {
    private static let logger = Logger(subsystem: "dev.rye.Clarissa", category: "SchemaMigrator")

    /// Registered migrations, keyed by source version.
    private static let migrations: [SchemaVersion: @Sendable (Data) throws -> Data] = [
        // v1 → v2: No structural changes needed — new fields are Optional with nil defaults.
        .v1: { data in data },
        // v2 → v3: SharedResult gains optional chainId field. No structural migration needed.
        .v2: { data in data }
    ]

    /// Detect the schema version from raw persisted data.
    /// Returns `.v1` if the data predates versioning (no `schemaVersion` field).
    static func detectVersion(from data: Data) -> SchemaVersion {
        // Try to decode just the version field
        struct VersionProbe: Decodable {
            let schemaVersion: SchemaVersion?
        }

        guard let probe = try? JSONDecoder().decode(VersionProbe.self, from: data) else {
            return .v1
        }
        return probe.schemaVersion ?? .v1
    }

    /// Migrate raw data from its detected version up to the target version.
    /// Returns the migrated data, ready to decode into the target type.
    static func migrate(data: Data, to target: SchemaVersion = .current) throws -> Data {
        var currentVersion = detectVersion(from: data)
        var currentData = data

        while currentVersion < target {
            guard let migration = migrations[currentVersion] else {
                logger.warning("No migration registered for v\(currentVersion.rawValue) → v\(currentVersion.rawValue + 1). Data will be passed through unchanged.")
                // No migration needed — advance version
                if let next = SchemaVersion(rawValue: currentVersion.rawValue + 1) {
                    currentVersion = next
                } else {
                    break
                }
                continue
            }

            guard let nextVersion = SchemaVersion(rawValue: currentVersion.rawValue + 1) else {
                logger.error("Missing SchemaVersion case for rawValue \(currentVersion.rawValue + 1)")
                break
            }
            logger.info("Migrating schema v\(currentVersion.rawValue) → v\(nextVersion.rawValue)")
            currentData = try migration(currentData)
            currentVersion = nextVersion
        }

        return currentData
    }
}
