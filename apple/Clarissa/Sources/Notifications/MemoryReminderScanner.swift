import Foundation

/// Scans stored memories for time-sensitive content and surfaces them as notifications.
/// Detects patterns like "follow up with X this week", "check Y by Friday", etc.
@MainActor
public final class MemoryReminderScanner {
    public static let shared = MemoryReminderScanner()

    static let settingsKey = "memoryRemindersEnabled"

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.settingsKey)
    }

    private init() {}

    /// Scan memories for time-sensitive content and schedule notifications
    public func scanAndNotify() async {
        guard isEnabled else { return }

        let memories = await MemoryManager.shared.getAllMemories()
        let now = Date()
        let calendar = Calendar.current

        for memory in memories {
            // Skip memories that are too old to be relevant as reminders
            guard let createdAt = memory.createdAt,
                  calendar.dateComponents([.day], from: createdAt, to: now).day ?? 0 <= 14 else {
                continue
            }

            // Check if memory has time-sensitive language
            guard let triggerDate = detectTimeSensitivity(in: memory.content, referenceDate: createdAt) else {
                continue
            }

            // Only notify if the trigger date is today or within the next 24 hours
            let hoursUntilTrigger = calendar.dateComponents([.hour], from: now, to: triggerDate).hour ?? 0
            guard hoursUntilTrigger >= -2 && hoursUntilTrigger <= 24 else { continue }

            // Check if we've already notified for this memory
            let notifiedKey = "memoryNotified-\(memory.id)"
            guard !UserDefaults.standard.bool(forKey: notifiedKey) else { continue }

            // Schedule notification
            NotificationManager.shared.scheduleMemoryReminder(
                memoryContent: memory.content,
                memoryId: memory.id
            )

            // Mark as notified
            UserDefaults.standard.set(true, forKey: notifiedKey)
        }
    }

    // MARK: - Time Sensitivity Detection

    /// Detect time-sensitive phrases and estimate when the reminder should fire
    private func detectTimeSensitivity(in text: String, referenceDate: Date) -> Date? {
        let lower = text.lowercased()
        let calendar = Calendar.current

        // "this week" / "by end of week"
        if lower.contains("this week") || lower.contains("end of week") || lower.contains("by friday") {
            // Target: Friday of the reference date's week
            let weekday = calendar.component(.weekday, from: referenceDate)
            let daysUntilFriday = (6 - weekday + 7) % 7  // 6 = Friday in Calendar's Sunday=1 system
            // If today IS Friday (0 days), "by Friday" means today, not next week
            return calendar.date(byAdding: .day, value: daysUntilFriday, to: referenceDate)
        }

        // "tomorrow"
        if lower.contains("tomorrow") {
            return calendar.date(byAdding: .day, value: 1, to: referenceDate)
        }

        // "next week"
        if lower.contains("next week") {
            return calendar.date(byAdding: .weekOfYear, value: 1, to: referenceDate)
        }

        // "in N days"
        let daysPattern = #"in (\d+) days?"#
        if let regex = try? NSRegularExpression(pattern: daysPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           match.numberOfRanges > 1,
           let range = Range(match.range(at: 1), in: text),
           let days = Int(text[range]) {
            return calendar.date(byAdding: .day, value: days, to: referenceDate)
        }

        // Day names: "on Monday", "by Tuesday"
        let dayNames = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
        for (index, dayName) in dayNames.enumerated() {
            if lower.contains(dayName) {
                let targetWeekday = index < 6 ? index + 2 : 1  // Calendar weekday: Sunday=1, Monday=2, ..., Saturday=7
                let currentWeekday = calendar.component(.weekday, from: referenceDate)
                let daysAhead = (targetWeekday - currentWeekday + 7) % 7
                // If daysAhead is 0, the target day is today — schedule for next week's occurrence
                return calendar.date(byAdding: .day, value: daysAhead == 0 ? 7 : daysAhead, to: referenceDate)
            }
        }

        // Follow-up patterns without specific timing: "follow up", "check in", "get back to"
        if lower.contains("follow up") || lower.contains("check in with") || lower.contains("get back to") {
            // Default to 2 days after the memory was created
            return calendar.date(byAdding: .day, value: 2, to: referenceDate)
        }

        return nil
    }
}

// MARK: - Memory Extension

/// Lightweight memory representation for scanning
struct ScannableMemory: Sendable {
    let id: String
    let content: String
    let createdAt: Date?
}

/// Extension to expose memories in a scannable format
extension MemoryManager {
    func getAllMemories() async -> [ScannableMemory] {
        let memories = await getAll()
        return memories.map { memory in
            ScannableMemory(
                id: memory.id.uuidString,
                content: memory.content,
                createdAt: memory.createdAt
            )
        }
    }
}
