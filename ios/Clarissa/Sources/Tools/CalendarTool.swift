import Foundation
import EventKit

/// Tool for calendar operations
final class CalendarTool: ClarissaTool, @unchecked Sendable {
    let name = "calendar"
    let description = "Create, read, and manage calendar events. Can create new events, list upcoming events, and search for events."
    let priority = ToolPriority.core
    let requiresConfirmation = true
    
    private let eventStore = EKEventStore()
    
    var parametersSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "action": [
                    "type": "string",
                    "enum": ["create", "list", "search"],
                    "description": "The action to perform"
                ],
                "title": [
                    "type": "string",
                    "description": "Event title (required for create)"
                ],
                "startDate": [
                    "type": "string",
                    "description": "Start date/time in ISO 8601 format"
                ],
                "endDate": [
                    "type": "string",
                    "description": "End date/time in ISO 8601 format"
                ],
                "location": [
                    "type": "string",
                    "description": "Event location"
                ],
                "notes": [
                    "type": "string",
                    "description": "Event notes"
                ],
                "daysAhead": [
                    "type": "integer",
                    "description": "Days ahead to list (default: 7)"
                ],
                "query": [
                    "type": "string",
                    "description": "Search query"
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
        
        // Request access if needed
        let granted = try await requestAccess()
        guard granted else {
            throw ToolError.permissionDenied("Calendar access denied")
        }
        
        switch action {
        case "create":
            return try await createEvent(args)
        case "list":
            return try await listEvents(args)
        case "search":
            return try await searchEvents(args)
        default:
            throw ToolError.invalidArguments("Unknown action: \(action)")
        }
    }
    
    private func requestAccess() async throws -> Bool {
        if #available(iOS 17.0, *) {
            return try await eventStore.requestFullAccessToEvents()
        } else {
            return try await eventStore.requestAccess(to: .event)
        }
    }
    
    private func createEvent(_ args: [String: Any]) async throws -> String {
        guard let title = args["title"] as? String else {
            throw ToolError.invalidArguments("Title is required for creating events")
        }

        // Check for default calendar
        guard let calendar = eventStore.defaultCalendarForNewEvents else {
            throw ToolError.notAvailable("No calendar available. Please ensure you have at least one calendar configured on this device.")
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.calendar = calendar

        // Parse dates with flexible formatting
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Try parsing with fractional seconds first, then without
        func parseDate(_ string: String) -> Date? {
            if let date = formatter.date(from: string) {
                return date
            }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: string)
        }

        if let startStr = args["startDate"] as? String, let start = parseDate(startStr) {
            event.startDate = start
        } else {
            event.startDate = Date()
        }

        if let endStr = args["endDate"] as? String, let end = parseDate(endStr) {
            event.endDate = end
        } else {
            event.endDate = event.startDate.addingTimeInterval(3600) // 1 hour default
        }

        // Validate dates
        if event.endDate < event.startDate {
            event.endDate = event.startDate.addingTimeInterval(3600)
        }

        if let location = args["location"] as? String {
            event.location = location
        }

        if let notes = args["notes"] as? String {
            event.notes = notes
        }

        try eventStore.save(event, span: .thisEvent)

        // Reset formatter for output
        formatter.formatOptions = [.withInternetDateTime]

        let response: [String: Any] = [
            "success": true,
            "eventId": event.eventIdentifier ?? "",
            "title": title,
            "startDate": formatter.string(from: event.startDate),
            "endDate": formatter.string(from: event.endDate),
            "calendar": calendar.title
        ]

        let data = try JSONSerialization.data(withJSONObject: response)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
    
    private func listEvents(_ args: [String: Any]) async throws -> String {
        let daysAhead = args["daysAhead"] as? Int ?? 7
        let startDate = Date()
        let endDate = Calendar.current.date(byAdding: .day, value: daysAhead, to: startDate)!
        
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let events = eventStore.events(matching: predicate)
        
        let formatter = ISO8601DateFormatter()
        let eventList = events.prefix(20).map { event -> [String: Any] in
            [
                "title": event.title ?? "",
                "startDate": formatter.string(from: event.startDate),
                "endDate": formatter.string(from: event.endDate),
                "location": event.location ?? "",
                "isAllDay": event.isAllDay
            ]
        }
        
        let result = try JSONSerialization.data(withJSONObject: ["events": eventList])
        return String(data: result, encoding: .utf8) ?? "{}"
    }
    
    private func searchEvents(_ args: [String: Any]) async throws -> String {
        guard let query = args["query"] as? String else {
            throw ToolError.invalidArguments("Query is required for search")
        }
        
        let startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
        let endDate = Calendar.current.date(byAdding: .month, value: 6, to: Date())!
        
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let events = eventStore.events(matching: predicate)
            .filter { $0.title?.localizedCaseInsensitiveContains(query) ?? false }
        
        let formatter = ISO8601DateFormatter()
        let eventList = events.prefix(10).map { event -> [String: Any] in
            [
                "title": event.title ?? "",
                "startDate": formatter.string(from: event.startDate),
                "location": event.location ?? ""
            ]
        }
        
        let result = try JSONSerialization.data(withJSONObject: ["events": eventList, "query": query])
        return String(data: result, encoding: .utf8) ?? "{}"
    }
}

