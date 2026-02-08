import Foundation
import EventKit
import os.log

/// Collects weather, calendar, and reminder data for the morning widget.
/// Called on app launch and by the widget timeline provider.
@MainActor
final class MorningDataCollector {
    static let shared = MorningDataCollector()

    private static let logger = Logger(subsystem: "dev.rye.Clarissa", category: "MorningWidget")

    private init() {}

    /// Collect all morning briefing data and save to App Group for widget display
    func collectAndSave() async {
        let weather = await fetchWeatherSummary()
        let event = await fetchNextCalendarEvent()
        let reminder = await fetchTopReminder()

        let data = WidgetMorningData(
            weatherSummary: weather,
            nextEvent: event?.title,
            nextEventTime: event?.startDate,
            topReminder: reminder,
            lastUpdated: Date()
        )

        WidgetDataManager.shared.saveMorningData(data)
        Self.logger.info("Morning data collected: weather=\(weather ?? "nil"), event=\(event?.title ?? "nil"), reminder=\(reminder ?? "nil")")
    }

    // MARK: - Data Fetching

    /// Fetch a short weather summary using the weather tool's cached data
    private func fetchWeatherSummary() async -> String? {
        // Try to get cached weather from OfflineManager first
        if let cached = OfflineManager.shared.getCachedResult(name: "weather") {
            // Extract a short summary from the JSON result
            return parseWeatherSummary(from: cached.result)
        }

        // Otherwise try to execute the weather tool directly
        do {
            let result = try await ToolRegistry.shared.execute(
                name: "weather",
                arguments: "{\"query\": \"current weather\"}"
            )
            return parseWeatherSummary(from: result)
        } catch {
            Self.logger.debug("Weather fetch failed for morning widget: \(error.localizedDescription)")
            return nil
        }
    }

    /// Parse a short weather summary from tool JSON output
    private func parseWeatherSummary(from json: String) -> String? {
        // Try to extract temperature and condition from the JSON
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Fallback: just take the first line
            return json.components(separatedBy: "\n").first.map { String($0.prefix(60)) }
        }

        if let temp = dict["temperature"] as? String,
           let condition = dict["condition"] as? String {
            return "\(temp), \(condition)"
        }

        if let summary = dict["summary"] as? String {
            return String(summary.prefix(60))
        }

        return nil
    }

    /// Fetch the next upcoming calendar event
    private func fetchNextCalendarEvent() async -> (title: String, startDate: Date)? {
        let store = EKEventStore()

        // Check authorization
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            return nil
        }

        let now = Date()
        guard let endOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: now) else {
            return nil
        }

        let predicate = store.predicateForEvents(withStart: now, end: endOfDay, calendars: nil)
        let events = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }

        guard let next = events.first else { return nil }
        return (title: next.title ?? "Event", startDate: next.startDate)
    }

    /// Fetch the top incomplete reminder
    private func fetchTopReminder() async -> String? {
        let store = EKEventStore()

        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let predicate = store.predicateForIncompleteReminders(
                withDueDateStarting: nil,
                ending: nil,
                calendars: nil
            )
            store.fetchReminders(matching: predicate) { reminders in
                // Sort by due date (soonest first), then take the first one
                let sorted = (reminders ?? [])
                    .sorted { ($0.dueDateComponents?.date ?? .distantFuture) < ($1.dueDateComponents?.date ?? .distantFuture) }
                continuation.resume(returning: sorted.first?.title)
            }
        }
    }
}
