import Foundation
import EventKit

/// Sendable reminder data for crossing concurrency boundaries
private struct ReminderData: Sendable {
    let id: String
    let title: String
    let isCompleted: Bool
    let dueDate: String?
    let priority: Int

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "title": title,
            "isCompleted": isCompleted
        ]
        if let dueDate = dueDate {
            dict["dueDate"] = dueDate
        }
        if priority > 0 {
            dict["priority"] = priority
        }
        return dict
    }
}

/// Tool for managing reminders
final class RemindersTool: ClarissaTool, @unchecked Sendable {
    let name = "reminders"
    let description = "Create, list, and complete reminders. Can set due dates and priorities."
    let priority = ToolPriority.extended
    let requiresConfirmation = true

    private let eventStore = EKEventStore()
    
    var parametersSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "action": [
                    "type": "string",
                    "enum": ["list", "create", "complete"],
                    "description": "The action to perform"
                ],
                "title": [
                    "type": "string",
                    "description": "Title for new reminder (required for create)"
                ],
                "notes": [
                    "type": "string",
                    "description": "Notes for the reminder"
                ],
                "dueDate": [
                    "type": "string",
                    "description": "Due date in ISO8601 format"
                ],
                "priority": [
                    "type": "integer",
                    "description": "Priority (0=none, 1=high, 5=medium, 9=low)"
                ],
                "reminderId": [
                    "type": "string",
                    "description": "Reminder ID (required for complete)"
                ],
                "listName": [
                    "type": "string",
                    "description": "Name of reminder list to use"
                ]
            ],
            "required": ["action"]
        ]
    }
    
    func execute(arguments: String) async throws -> String {
        guard let data = arguments.data(using: .utf8),
              let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = args["action"] as? String else {
            throw ToolError.invalidArguments("Missing action parameter")
        }
        
        // Request access
        let granted = try await eventStore.requestFullAccessToReminders()
        guard granted else {
            throw ToolError.notAvailable("Reminders access denied. Please enable in Settings.")
        }
        
        switch action {
        case "list":
            return try await listReminders(args)
        case "create":
            return try await createReminder(args)
        case "complete":
            return try await completeReminder(args)
        default:
            throw ToolError.invalidArguments("Unknown action: \(action)")
        }
    }
    
    private func listReminders(_ args: [String: Any]) async throws -> String {
        let calendars = eventStore.calendars(for: .reminder)
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: Date().addingTimeInterval(30 * 24 * 60 * 60), // Next 30 days
            calendars: calendars
        )

        // Use Sendable struct to cross concurrency boundary
        let reminderDataList: [ReminderData] = try await withCheckedThrowingContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { result in
                let reminders = result ?? []
                let list = reminders.prefix(20).map { reminder -> ReminderData in
                    let dueDate: String? = reminder.dueDateComponents?.date.map {
                        ISO8601DateFormatter().string(from: $0)
                    }
                    return ReminderData(
                        id: reminder.calendarItemIdentifier,
                        title: reminder.title ?? "Untitled",
                        isCompleted: reminder.isCompleted,
                        dueDate: dueDate,
                        priority: reminder.priority
                    )
                }
                continuation.resume(returning: Array(list))
            }
        }

        let reminderList = reminderDataList.map { $0.toDictionary() }

        let response: [String: Any] = [
            "count": reminderList.count,
            "reminders": reminderList
        ]

        let responseData = try JSONSerialization.data(withJSONObject: response)
        return String(data: responseData, encoding: .utf8) ?? "{}"
    }
    
    private func createReminder(_ args: [String: Any]) async throws -> String {
        guard let title = args["title"] as? String else {
            throw ToolError.invalidArguments("Title is required for creating reminders")
        }
        
        guard let calendar = eventStore.defaultCalendarForNewReminders() else {
            throw ToolError.notAvailable("No reminder list available")
        }
        
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.calendar = calendar
        
        if let notes = args["notes"] as? String {
            reminder.notes = notes
        }
        
        if let dueDateStr = args["dueDate"] as? String,
           let dueDate = ISO8601DateFormatter().date(from: dueDateStr) {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
        }
        
        if let priority = args["priority"] as? Int {
            reminder.priority = priority
        }
        
        try eventStore.save(reminder, commit: true)
        
        let response: [String: Any] = [
            "success": true,
            "id": reminder.calendarItemIdentifier,
            "title": title
        ]
        
        let responseData = try JSONSerialization.data(withJSONObject: response)
        return String(data: responseData, encoding: .utf8) ?? "{}"
    }
    
    private func completeReminder(_ args: [String: Any]) async throws -> String {
        guard let reminderId = args["reminderId"] as? String else {
            throw ToolError.invalidArguments("reminderId is required")
        }
        
        guard let reminder = eventStore.calendarItem(withIdentifier: reminderId) as? EKReminder else {
            throw ToolError.executionFailed("Reminder not found")
        }
        
        reminder.isCompleted = true
        reminder.completionDate = Date()
        try eventStore.save(reminder, commit: true)
        
        return "{\"success\": true, \"message\": \"Reminder completed\"}"
    }
}

