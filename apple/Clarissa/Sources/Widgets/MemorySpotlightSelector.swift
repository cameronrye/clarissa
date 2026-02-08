import Foundation
import os.log

/// Selects a contextually relevant memory to surface in the Memory Spotlight widget.
/// Scoring considers: confidence, time-of-day relevance, recency, and category.
actor MemorySpotlightSelector {
    static let shared = MemorySpotlightSelector()

    private static let logger = Logger(subsystem: "dev.rye.Clarissa", category: "MemorySpotlight")

    private init() {}

    /// Select the best memory to spotlight and save it to App Group
    func selectAndSave() async {
        guard let spotlight = await selectSpotlight() else { return }
        await WidgetDataManager.shared.saveMemorySpotlight(spotlight)
        Self.logger.info("Memory spotlight selected (length: \(spotlight.memoryContent.count))")
    }

    /// Select the most relevant memory to spotlight based on contextual scoring
    func selectSpotlight() async -> WidgetMemorySpotlight? {
        let memories = await MemoryManager.shared.getAll()
        guard !memories.isEmpty else { return nil }

        let hour = Calendar.current.component(.hour, from: Date())

        let scored: [(Memory, Double, String)] = memories.map { memory in
            var score = Double(memory.confidence ?? 0.5)
            var reason = ""

            // Time-of-day relevance
            switch memory.category {
            case .routine:
                if hour >= 6 && hour < 10 {
                    score += 0.3
                    reason = "Part of your morning routine"
                } else if hour >= 17 && hour < 21 {
                    score += 0.2
                    reason = "Evening routine"
                }
            case .preference:
                if hour >= 11 && hour < 14 {
                    score += 0.15
                    reason = "Something you enjoy"
                } else {
                    reason = "A preference to remember"
                }
            case .relationship:
                reason = "Someone important to you"
                score += 0.1
            case .fact:
                reason = "A fact you saved"
            default:
                reason = "From your memories"
            }

            // Recency boost — recently accessed memories are more relevant
            if let lastAccessed = memory.lastAccessedAt,
               Date().timeIntervalSince(lastAccessed) < 86400 * 7 {
                score += 0.2
                if reason.isEmpty { reason = "Recently on your mind" }
            }

            // Slight randomness to rotate through memories over time
            // Use the hour as a seed-like offset to surface different memories at different times
            let hourOffset = Double(hour) * 0.01
            score += hourOffset

            return (memory, score, reason)
        }

        guard let top = scored.max(by: { $0.1 < $1.1 }) else { return nil }

        return WidgetMemorySpotlight(
            memoryContent: top.0.content,
            memoryTopics: top.0.topics,
            reason: top.2,
            lastUpdated: Date()
        )
    }
}
