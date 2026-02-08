import Foundation
import EventKit

/// Monitors upcoming calendar events and sends "heads up" notifications
/// for meetings with attendees the user hasn't interacted with recently.
@MainActor
public final class CalendarMonitor: ObservableObject {
    public static let shared = CalendarMonitor()

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.settingsKey)
            if !isEnabled { stopMonitoring() }
        }
    }

    /// Minutes before an event to send the alert (default 30)
    @Published var alertMinutesBefore: Int {
        didSet { UserDefaults.standard.set(alertMinutesBefore, forKey: "calendarAlertMinutes") }
    }

    /// Minimum number of attendees to trigger a prep notification
    @Published var minAttendeesForAlert: Int {
        didSet { UserDefaults.standard.set(minAttendeesForAlert, forKey: "calendarAlertMinAttendees") }
    }

    static let settingsKey = "calendarAlertingEnabled"
    private let eventStore = EKEventStore()
    private var scanTimer: Timer?

    private init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: Self.settingsKey)
        self.alertMinutesBefore = UserDefaults.standard.object(forKey: "calendarAlertMinutes") as? Int ?? 30
        self.minAttendeesForAlert = UserDefaults.standard.object(forKey: "calendarAlertMinAttendees") as? Int ?? 3
    }

    /// Start monitoring calendar events (call from app launch)
    public func startMonitoring() {
        guard isEnabled else { return }

        // Invalidate any existing timer to prevent leaks on repeated calls
        stopMonitoring()

        // Listen for calendar changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(calendarChanged),
            name: .EKEventStoreChanged,
            object: eventStore
        )

        // Scan every 15 minutes
        scanTimer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.scanUpcomingEvents()
            }
        }

        // Initial scan
        Task { await scanUpcomingEvents() }
    }

    /// Stop monitoring
    func stopMonitoring() {
        scanTimer?.invalidate()
        scanTimer = nil
        NotificationCenter.default.removeObserver(self, name: .EKEventStoreChanged, object: eventStore)
    }

    @objc private func calendarChanged() {
        Task { @MainActor in
            await scanUpcomingEvents()
        }
    }

    /// Request calendar access if not yet granted
    func requestAccessIfNeeded() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .fullAccess || status == .authorized { return true }
        if status == .notDetermined {
            do {
                if #available(iOS 17.0, macOS 14.0, *) {
                    return try await eventStore.requestFullAccessToEvents()
                } else {
                    return try await eventStore.requestAccess(to: .event)
                }
            } catch {
                ClarissaLogger.notifications.error("Calendar access request failed: \(error.localizedDescription)")
                return false
            }
        }
        return false
    }

    /// Scan upcoming events and schedule alerts for qualifying meetings
    func scanUpcomingEvents() async {
        guard isEnabled else { return }

        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .notDetermined {
            let granted = await requestAccessIfNeeded()
            guard granted else { return }
        } else if status != .fullAccess && status != .authorized {
            return
        }

        let calendar = Calendar.current
        let now = Date()
        guard let windowEnd = calendar.date(byAdding: .hour, value: 4, to: now) else { return }

        let predicate = eventStore.predicateForEvents(
            withStart: now,
            end: windowEnd,
            calendars: nil
        )

        let events = eventStore.events(matching: predicate)

        for event in events {
            guard let attendees = event.attendees,
                  attendees.count >= minAttendeesForAlert else { continue }

            // Count attendees that aren't the organizer/current user
            let otherAttendees = attendees.filter { !$0.isCurrentUser }
            guard otherAttendees.count >= minAttendeesForAlert else { continue }

            // Schedule an alert notification
            NotificationManager.shared.scheduleCalendarAlert(
                eventTitle: event.title ?? "Upcoming meeting",
                attendeeCount: otherAttendees.count,
                minutesBefore: alertMinutesBefore,
                eventDate: event.startDate
            )
        }
    }
}
