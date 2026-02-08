import Foundation
import UserNotifications
import os.log

/// Manages local notifications for Clarissa: scheduled check-ins, calendar alerts, and memory reminders.
@MainActor
public final class NotificationManager: NSObject, ObservableObject {
    public static let shared = NotificationManager()

    @Published var isAuthorized: Bool = false

    // MARK: - Notification Categories

    /// Category identifiers for actionable notifications
    enum Category: String {
        case checkIn = "clarissa.checkin"
        case calendarAlert = "clarissa.calendar"
        case memoryReminder = "clarissa.memory"
    }

    /// Action identifiers for notification buttons
    enum Action: String {
        case reply = "clarissa.action.reply"
        case snooze = "clarissa.action.snooze"
        case open = "clarissa.action.open"
        case dismiss = "clarissa.action.dismiss"
    }

    private override init() {
        super.init()
    }

    // MARK: - Authorization

    /// Request notification authorization
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            isAuthorized = granted
            if granted {
                registerCategories()
            }
            ClarissaLogger.notifications.info("Notification authorization: \(granted)")
            return granted
        } catch {
            ClarissaLogger.notifications.error("Notification auth failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Check current authorization status
    public func checkAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
    }

    // MARK: - Category Registration

    /// Register actionable notification categories
    private func registerCategories() {
        let replyAction = UNTextInputNotificationAction(
            identifier: Action.reply.rawValue,
            title: "Reply",
            options: [],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Ask Clarissa..."
        )

        let snoozeAction = UNNotificationAction(
            identifier: Action.snooze.rawValue,
            title: "Snooze 1hr",
            options: []
        )

        let openAction = UNNotificationAction(
            identifier: Action.open.rawValue,
            title: "Open",
            options: .foreground
        )

        let dismissAction = UNNotificationAction(
            identifier: Action.dismiss.rawValue,
            title: "Dismiss",
            options: .destructive
        )

        // Check-in category: reply or snooze
        let checkInCategory = UNNotificationCategory(
            identifier: Category.checkIn.rawValue,
            actions: [replyAction, snoozeAction, openAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )

        // Calendar alert: open or snooze
        let calendarCategory = UNNotificationCategory(
            identifier: Category.calendarAlert.rawValue,
            actions: [openAction, snoozeAction, dismissAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )

        // Memory reminder: open or dismiss
        let memoryCategory = UNNotificationCategory(
            identifier: Category.memoryReminder.rawValue,
            actions: [openAction, dismissAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )

        UNUserNotificationCenter.current().setNotificationCategories([
            checkInCategory,
            calendarCategory,
            memoryCategory,
        ])
    }

    // MARK: - Schedule Notifications

    /// Schedule a local notification for a check-in result
    public func scheduleCheckInNotification(
        title: String,
        body: String,
        checkInId: String,
        at date: Date
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = String(body.prefix(200))  // Truncate for notification
        content.sound = .default
        content.categoryIdentifier = Category.checkIn.rawValue
        content.userInfo = ["checkInId": checkInId, "type": "checkin"]

        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(
            identifier: "checkin-\(checkInId)-\(date.timeIntervalSince1970)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                ClarissaLogger.notifications.error("Failed to schedule check-in: \(error.localizedDescription)")
            }
        }
    }

    /// Schedule a calendar alert notification
    public func scheduleCalendarAlert(
        eventTitle: String,
        attendeeCount: Int,
        minutesBefore: Int,
        eventDate: Date
    ) {
        let content = UNMutableNotificationContent()
        content.title = "Heads up: \(eventTitle)"
        content.body = "Your \(eventTitle) has \(attendeeCount) attendee\(attendeeCount == 1 ? "" : "s") you haven't met — want a prep?"
        content.sound = .default
        content.categoryIdentifier = Category.calendarAlert.rawValue
        content.userInfo = ["eventTitle": eventTitle, "type": "calendar"]

        let triggerDate = eventDate.addingTimeInterval(-Double(minutesBefore * 60))
        guard triggerDate > Date() else { return }

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: triggerDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(
            identifier: "calendar-\(eventTitle)-\(Int(eventDate.timeIntervalSince1970))",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                ClarissaLogger.notifications.error("Failed to schedule calendar alert: \(error.localizedDescription)")
            }
        }
    }

    /// Schedule a memory reminder notification
    public func scheduleMemoryReminder(memoryContent: String, memoryId: String) {
        let content = UNMutableNotificationContent()
        content.title = "Memory Reminder"
        content.body = String(memoryContent.prefix(200))
        content.sound = .default
        content.categoryIdentifier = Category.memoryReminder.rawValue
        content.userInfo = ["memoryId": memoryId, "type": "memory"]

        // Deliver within the next few seconds (immediate)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)

        let request = UNNotificationRequest(
            identifier: "memory-\(memoryId)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                ClarissaLogger.notifications.error("Failed to schedule memory reminder: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Manage Notifications

    /// Remove all pending check-in notifications for a given schedule
    func cancelCheckInNotifications(checkInId: String) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let matching = requests.filter { $0.identifier.hasPrefix("checkin-\(checkInId)") }
            center.removePendingNotificationRequests(withIdentifiers: matching.map(\.identifier))
        }
    }

    /// Remove all pending notifications
    func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    /// Get count of pending notifications
    func pendingNotificationCount() async -> Int {
        await UNUserNotificationCenter.current().pendingNotificationRequests().count
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    /// Handle notification tap / action when app is in foreground
    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        // Extract all values from response before crossing isolation boundary
        let actionId = response.actionIdentifier
        let replyText = (response as? UNTextInputNotificationResponse)?.userText
        let userInfo = response.notification.request.content.userInfo
        let notificationId = response.notification.request.identifier
        let notificationTitle = response.notification.request.content.title
        let notificationBody = response.notification.request.content.body
        // Extract userInfo values we need
        let eventType = userInfo["type"] as? String
        let eventTitle = userInfo["eventTitle"] as? String

        // Handle the action asynchronously but always call completionHandler synchronously
        // to guarantee iOS receives it before the process is suspended
        Task { @MainActor in
            switch actionId {
            case Action.reply.rawValue:
                if let replyText {
                    // User replied from the notification — start a new conversation to avoid
                    // injecting unrelated content into the current session
                    let appState = AppState.shared
                    appState.requestNewConversation = true
                    appState.pendingShortcutQuestion = replyText
                    appState.pendingQuestionSource = .notification
                }

            case Action.snooze.rawValue:
                // Re-schedule the notification 1 hour from now
                let content = UNMutableNotificationContent()
                content.title = notificationTitle
                content.body = notificationBody
                content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)
                let request = UNNotificationRequest(
                    identifier: notificationId + "-snoozed",
                    content: content,
                    trigger: trigger
                )
                try? await UNUserNotificationCenter.current().add(request)

            case Action.open.rawValue, UNNotificationDefaultActionIdentifier:
                // Open the app (already happening via .foreground option)
                if eventType == "calendar", let eventTitle {
                    let appState = AppState.shared
                    appState.requestNewConversation = true
                    appState.pendingShortcutQuestion = "Help me prepare for \(eventTitle)"
                    appState.pendingQuestionSource = .notification
                }

            default:
                break
            }
        }

        // Always call completionHandler synchronously — must not be deferred into async Task
        completionHandler()
    }

    /// Show notifications even when app is in foreground
    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

// MARK: - Logger Extension

extension ClarissaLogger {
    static let notifications = Logger(subsystem: "dev.rye.Clarissa", category: "Notifications")
}
