import SwiftUI

// MARK: - Tool Result Display Protocol

/// Protocol for tool results that can render themselves in the chat UI
/// Each tool can provide a custom view for displaying its results in an expandable card
protocol ToolResultDisplayable {
    /// The tool name this result is for
    static var toolName: String { get }

    /// Parse JSON result string into this type
    init?(jsonResult: String)

    /// The SwiftUI view type for displaying this result
    associatedtype ResultView: View

    /// Create a view to display this result
    @MainActor
    func makeResultView() -> ResultView
}

// MARK: - Weather Result

/// Parsed weather data for display
struct WeatherResult: ToolResultDisplayable {
    static let toolName = "weather"

    let locationName: String?
    let temperature: Double
    let temperatureUnit: String
    let condition: String
    let humidity: Double
    let feelsLike: Double
    let windSpeed: Double
    let windSpeedUnit: String
    let forecast: [ForecastDay]?

    struct ForecastDay: Identifiable {
        let id = UUID()
        let date: Date
        let condition: String
        let high: Double
        let low: Double
        let precipitationChance: Double
    }

    init?(jsonResult: String) {
        guard let data = jsonResult.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // Check for error response
        if json["error"] as? Bool == true {
            return nil
        }

        guard let current = json["current"] as? [String: Any],
              let tempDict = current["temperature"] as? [String: Any],
              let tempValue = tempDict["value"] as? Double,
              let tempUnit = tempDict["unit"] as? String,
              let condition = current["condition"] as? String else {
            return nil
        }

        self.temperature = tempValue
        self.temperatureUnit = tempUnit
        self.condition = condition
        self.humidity = current["humidity"] as? Double ?? 0
        self.feelsLike = (current["feelsLike"] as? [String: Any])?["value"] as? Double ?? tempValue

        if let windDict = current["windSpeed"] as? [String: Any] {
            self.windSpeed = windDict["value"] as? Double ?? 0
            self.windSpeedUnit = windDict["unit"] as? String ?? "mph"
        } else {
            self.windSpeed = 0
            self.windSpeedUnit = "mph"
        }

        // Parse location
        if let locationDict = json["location"] as? [String: Any] {
            self.locationName = locationDict["name"] as? String
        } else {
            self.locationName = nil
        }

        // Parse forecast if present
        if let forecastArray = json["forecast"] as? [[String: Any]] {
            let formatter = ISO8601DateFormatter()
            self.forecast = forecastArray.compactMap { day -> ForecastDay? in
                guard let dateStr = day["date"] as? String,
                      let date = formatter.date(from: dateStr),
                      let condition = day["condition"] as? String,
                      let highDict = day["highTemperature"] as? [String: Any],
                      let high = highDict["value"] as? Double,
                      let lowDict = day["lowTemperature"] as? [String: Any],
                      let low = lowDict["value"] as? Double else {
                    return nil
                }
                let precip = day["precipitationChance"] as? Double ?? 0
                return ForecastDay(date: date, condition: condition, high: high, low: low, precipitationChance: precip)
            }
        } else {
            self.forecast = nil
        }
    }

    @MainActor
    func makeResultView() -> some View {
        WeatherResultView(result: self)
    }
}

// MARK: - Weather Result View

struct WeatherResultView: View {
    let result: WeatherResult

    private var conditionIcon: String {
        let condition = result.condition.lowercased()
        if condition.contains("sun") || condition.contains("clear") {
            return "sun.max.fill"
        } else if condition.contains("cloud") && condition.contains("part") {
            return "cloud.sun.fill"
        } else if condition.contains("cloud") {
            return "cloud.fill"
        } else if condition.contains("rain") || condition.contains("shower") {
            return "cloud.rain.fill"
        } else if condition.contains("thunder") || condition.contains("storm") {
            return "cloud.bolt.rain.fill"
        } else if condition.contains("snow") {
            return "cloud.snow.fill"
        } else if condition.contains("fog") || condition.contains("mist") {
            return "cloud.fog.fill"
        }
        return "cloud.fill"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with location and condition
            HStack {
                Image(systemName: conditionIcon)
                    .font(.title2)
                    .foregroundStyle(ClarissaTheme.gradient)

                VStack(alignment: .leading, spacing: 2) {
                    if let location = result.locationName {
                        Text(location)
                            .font(.subheadline.weight(.medium))
                    }
                    Text(result.condition)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(Int(result.temperature))\(result.temperatureUnit)")
                    .font(.title.weight(.semibold))
            }

            // Apple Weather attribution (required by WeatherKit per App Store guideline 5.2.5)
            // Must display Apple Weather trademark and legal attribution link
            Link(destination: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!) {
                HStack(spacing: 4) {
                    Image(systemName: "apple.logo")
                        .font(.caption)
                    Text("Weather")
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Data provided by Apple Weather. Tap for legal attribution.")
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Calendar Events Result

struct CalendarEventsResult: ToolResultDisplayable {
    static let toolName = "calendar"

    let events: [CalendarEvent]
    let isCreateResult: Bool
    let createdEvent: CalendarEvent?

    struct CalendarEvent: Identifiable {
        let id = UUID()
        let title: String
        let startDate: Date
        let endDate: Date?
        let location: String?
        let isAllDay: Bool
    }

    init?(jsonResult: String) {
        guard let data = jsonResult.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if json["error"] as? Bool == true {
            return nil
        }

        let formatter = ISO8601DateFormatter()

        // Check if this is a create result
        if let success = json["success"] as? Bool, success,
           let title = json["title"] as? String,
           let startStr = json["startDate"] as? String,
           let start = formatter.date(from: startStr) {
            self.isCreateResult = true
            let endDate = (json["endDate"] as? String).flatMap { formatter.date(from: $0) }
            self.createdEvent = CalendarEvent(
                title: title,
                startDate: start,
                endDate: endDate,
                location: nil,
                isAllDay: false
            )
            self.events = []
            return
        }

        // Parse events list
        self.isCreateResult = false
        self.createdEvent = nil

        guard let eventsArray = json["events"] as? [[String: Any]] else {
            return nil
        }

        self.events = eventsArray.compactMap { event -> CalendarEvent? in
            guard let title = event["title"] as? String,
                  let startStr = event["startDate"] as? String,
                  let start = formatter.date(from: startStr) else {
                return nil
            }
            let endDate = (event["endDate"] as? String).flatMap { formatter.date(from: $0) }
            let location = event["location"] as? String
            let isAllDay = event["isAllDay"] as? Bool ?? false
            return CalendarEvent(title: title, startDate: start, endDate: endDate, location: location, isAllDay: isAllDay)
        }
    }

    @MainActor
    func makeResultView() -> some View {
        CalendarResultView(result: self)
    }
}

struct CalendarResultView: View {
    let result: CalendarEventsResult

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private func eventAccessibilityLabel(_ event: CalendarEventsResult.CalendarEvent) -> String {
        var label = event.title
        label += ", \(dateFormatter.string(from: event.startDate))"
        if !event.isAllDay {
            label += " at \(timeFormatter.string(from: event.startDate))"
        }
        if let location = event.location, !location.isEmpty {
            label += ", at \(location)"
        }
        return label
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if result.isCreateResult, let event = result.createdEvent {
                // Created event confirmation
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Event Created")
                        .font(.subheadline.weight(.medium))
                }

                Text(event.title)
                    .font(.headline)

                HStack {
                    Image(systemName: "calendar")
                        .foregroundStyle(.secondary)
                    Text(dateFormatter.string(from: event.startDate))
                    Text("at")
                        .foregroundStyle(.secondary)
                    Text(timeFormatter.string(from: event.startDate))
                }
                .font(.caption)
            } else {
                // Events list
                ForEach(result.events.prefix(5)) { event in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)

                            HStack(spacing: 4) {
                                Text(dateFormatter.string(from: event.startDate))
                                if !event.isAllDay {
                                    Text(timeFormatter.string(from: event.startDate))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if let location = event.location, !location.isEmpty {
                            Image(systemName: "location.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(eventAccessibilityLabel(event))
                }

                if result.events.count > 5 {
                    Text("+\(result.events.count - 5) more events")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(result.isCreateResult ? "Event created" : "\(result.events.count) calendar events")
    }
}

// MARK: - Reminders Result

struct RemindersResult: ToolResultDisplayable {
    static let toolName = "reminders"

    let reminders: [ReminderItem]
    let isCreateResult: Bool
    let createdTitle: String?

    struct ReminderItem: Identifiable {
        let id: String
        let title: String
        let dueDate: Date?
        let isCompleted: Bool
        let priority: Int
    }

    init?(jsonResult: String) {
        guard let data = jsonResult.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if json["error"] as? Bool == true {
            return nil
        }

        let formatter = ISO8601DateFormatter()

        // Check if this is a create result
        if let success = json["success"] as? Bool, success,
           let title = json["title"] as? String {
            self.isCreateResult = true
            self.createdTitle = title
            self.reminders = []
            return
        }

        self.isCreateResult = false
        self.createdTitle = nil

        guard let remindersArray = json["reminders"] as? [[String: Any]] else {
            return nil
        }

        self.reminders = remindersArray.compactMap { item -> ReminderItem? in
            guard let id = item["id"] as? String,
                  let title = item["title"] as? String else {
                return nil
            }
            let dueDate = (item["dueDate"] as? String).flatMap { formatter.date(from: $0) }
            let isCompleted = item["isCompleted"] as? Bool ?? false
            let priority = item["priority"] as? Int ?? 0
            return ReminderItem(id: id, title: title, dueDate: dueDate, isCompleted: isCompleted, priority: priority)
        }
    }

    @MainActor
    func makeResultView() -> some View {
        RemindersResultView(result: self)
    }
}

struct RemindersResultView: View {
    let result: RemindersResult

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    private func reminderAccessibilityLabel(_ reminder: RemindersResult.ReminderItem) -> String {
        var label = reminder.title
        if reminder.isCompleted {
            label += ", completed"
        }
        if let due = reminder.dueDate {
            label += ", due \(dateFormatter.string(from: due))"
        }
        if reminder.priority == 1 {
            label += ", high priority"
        }
        return label
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if result.isCreateResult, let title = result.createdTitle {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Reminder Created")
                        .font(.subheadline.weight(.medium))
                }
                Text(title)
                    .font(.headline)
            } else {
                ForEach(result.reminders.prefix(5)) { reminder in
                    HStack {
                        Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(reminder.isCompleted ? .green : .secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(reminder.title)
                                .font(.subheadline)
                                .lineLimit(1)

                            if let due = reminder.dueDate {
                                Text(dateFormatter.string(from: due))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        if reminder.priority == 1 {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)
                                .font(.caption)
                        }
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(reminderAccessibilityLabel(reminder))
                }

                if result.reminders.count > 5 {
                    Text("+\(result.reminders.count - 5) more reminders")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(result.isCreateResult ? "Reminder created" : "\(result.reminders.count) reminders")
    }
}

// MARK: - Calculator Result

struct CalculatorResult: ToolResultDisplayable {
    static let toolName = "calculator"

    let expression: String
    let result: Double

    init?(jsonResult: String) {
        guard let data = jsonResult.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if json["error"] as? Bool == true {
            return nil
        }

        guard let expr = json["expression"] as? String,
              let res = json["result"] as? Double else {
            return nil
        }

        self.expression = expr
        self.result = res
    }

    @MainActor
    func makeResultView() -> some View {
        CalculatorResultView(result: self)
    }
}

struct CalculatorResultView: View {
    let result: CalculatorResult

    var body: some View {
        HStack {
            Image(systemName: "equal.circle.fill")
                .font(.title3)
                .foregroundStyle(ClarissaTheme.gradient)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.expression)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(formatNumber(result.result))
                    .font(.title3.weight(.semibold))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(result.expression) equals \(formatNumber(result.result))")
    }

    private func formatNumber(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 && abs(value) < 1e10 {
            return String(format: "%.0f", value)
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 6
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

// MARK: - Contacts Result

struct ContactsResult: ToolResultDisplayable {
    static let toolName = "contacts"

    let contacts: [ContactItem]

    struct ContactItem: Identifiable {
        let id = UUID()
        let name: String
        let phoneNumbers: [String]
        let emails: [String]
    }

    init?(jsonResult: String) {
        guard let data = jsonResult.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if json["error"] as? Bool == true {
            return nil
        }

        guard let contactsArray = json["contacts"] as? [[String: Any]] else {
            return nil
        }

        self.contacts = contactsArray.compactMap { contact -> ContactItem? in
            guard let name = contact["name"] as? String else {
                return nil
            }
            let phones = contact["phoneNumbers"] as? [String] ?? []
            let emails = contact["emails"] as? [String] ?? []
            return ContactItem(name: name, phoneNumbers: phones, emails: emails)
        }
    }

    @MainActor
    func makeResultView() -> some View {
        ContactsResultView(result: self)
    }
}

struct ContactsResultView: View {
    let result: ContactsResult

    private func contactAccessibilityLabel(_ contact: ContactsResult.ContactItem) -> String {
        var label = contact.name
        if let phone = contact.phoneNumbers.first {
            label += ", phone \(phone)"
        }
        if let email = contact.emails.first {
            label += ", email \(email)"
        }
        return label
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(result.contacts.prefix(3)) { contact in
                HStack {
                    Image(systemName: "person.circle.fill")
                        .font(.title3)
                        .foregroundStyle(ClarissaTheme.gradient)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(contact.name)
                            .font(.subheadline.weight(.medium))

                        if let phone = contact.phoneNumbers.first {
                            Text(phone)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let email = contact.emails.first {
                            Text(email)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(contactAccessibilityLabel(contact))
            }

            if result.contacts.count > 3 {
                Text("+\(result.contacts.count - 3) more contacts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(result.contacts.count) contacts found")
    }
}

// MARK: - Location Result

struct LocationResult: ToolResultDisplayable {
    static let toolName = "location"

    let latitude: Double
    let longitude: Double
    let address: String?
    let city: String?
    let country: String?

    init?(jsonResult: String) {
        guard let data = jsonResult.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if json["error"] as? Bool == true {
            return nil
        }

        guard let lat = json["latitude"] as? Double,
              let lon = json["longitude"] as? Double else {
            return nil
        }

        self.latitude = lat
        self.longitude = lon
        self.address = json["address"] as? String
        self.city = json["city"] as? String
        self.country = json["country"] as? String
    }

    @MainActor
    func makeResultView() -> some View {
        LocationResultView(result: self)
    }
}

struct LocationResultView: View {
    let result: LocationResult

    private var accessibilityLabel: String {
        var parts: [String] = []
        if let address = result.address {
            parts.append(address)
        }
        if let city = result.city {
            parts.append(city)
        }
        if let country = result.country {
            parts.append(country)
        }
        return parts.isEmpty ? "Location found" : parts.joined(separator: ", ")
    }

    var body: some View {
        HStack {
            Image(systemName: "location.circle.fill")
                .font(.title3)
                .foregroundStyle(ClarissaTheme.gradient)

            VStack(alignment: .leading, spacing: 2) {
                if let address = result.address {
                    Text(address)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                }

                HStack(spacing: 4) {
                    if let city = result.city {
                        Text(city)
                    }
                    if let country = result.country {
                        Text(country)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Remember Result

struct RememberResult: ToolResultDisplayable {
    static let toolName = "remember"

    let success: Bool
    let content: String
    let message: String

    init?(jsonResult: String) {
        guard let data = jsonResult.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if json["error"] as? Bool == true {
            return nil
        }

        guard let success = json["success"] as? Bool,
              let content = json["content"] as? String else {
            return nil
        }

        self.success = success
        self.content = content
        self.message = json["message"] as? String ?? "Memory stored"
    }

    @MainActor
    func makeResultView() -> some View {
        RememberResultView(result: self)
    }
}

struct RememberResultView: View {
    let result: RememberResult

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Image(systemName: "brain.fill")
                    .font(.title3)
                    .foregroundStyle(ClarissaTheme.gradient)

                if result.success {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                        .offset(x: 10, y: 10)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Memory Saved")
                    .font(.subheadline.weight(.medium))

                Text(result.content)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Memory saved: \(result.content)")
    }
}

// MARK: - Web Fetch Result

struct WebFetchResult: ToolResultDisplayable {
    static let toolName = "web_fetch"

    let url: String
    let format: String
    let content: String
    let truncated: Bool
    let characterCount: Int

    /// Extract display-friendly host from URL
    private var displayHost: String {
        if let url = URL(string: url), let host = url.host {
            return host
        }
        return url
    }

    init?(jsonResult: String) {
        guard let data = jsonResult.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if json["error"] as? Bool == true {
            return nil
        }

        guard let url = json["url"] as? String,
              let content = json["content"] as? String else {
            return nil
        }

        self.url = url
        self.content = content
        self.format = json["format"] as? String ?? "text"
        self.truncated = json["truncated"] as? Bool ?? false
        self.characterCount = json["characterCount"] as? Int ?? content.count
    }

    @MainActor
    func makeResultView() -> some View {
        WebFetchResultView(result: self)
    }
}

struct WebFetchResultView: View {
    let result: WebFetchResult

    private var formatIcon: String {
        switch result.format {
        case "json": return "curlybraces"
        case "html": return "chevron.left.forwardslash.chevron.right"
        default: return "doc.text"
        }
    }

    private var displayHost: String {
        if let url = URL(string: result.url), let host = url.host {
            return host
        }
        return result.url
    }

    private var formattedCharCount: String {
        if result.characterCount >= 1000 {
            return String(format: "%.1fK", Double(result.characterCount) / 1000)
        }
        return "\(result.characterCount)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "globe")
                    .font(.title3)
                    .foregroundStyle(ClarissaTheme.gradient)

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayHost)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Label(result.format.uppercased(), systemImage: formatIcon)
                        Text("\(formattedCharCount) chars")
                        if result.truncated {
                            Text("(truncated)")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            // Content preview
            Text(result.content.prefix(200).trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .padding(.leading, 32)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Web content from \(displayHost), \(result.characterCount) characters")
    }
}

// MARK: - Image Analysis Result

struct ImageAnalysisResult: ToolResultDisplayable {
    static let toolName = "image_analysis"

    enum ResultType {
        case ocr(text: String, lineCount: Int)
        case classify(classifications: [(label: String, confidence: Double)])
        case detectFaces(faceCount: Int)
        case detectDocument(detected: Bool, confidence: Double)
        case pdfExtract(text: String, pageCount: Int, pagesExtracted: Int, truncated: Bool)
        case pdfOCR(text: String, pageCount: Int, pagesProcessed: Int, truncated: Bool)
        case pdfPageCount(pageCount: Int)
    }

    let resultType: ResultType

    init?(jsonResult: String) {
        guard let data = jsonResult.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if json["error"] as? Bool == true {
            return nil
        }

        // Detect result type from JSON structure
        if let text = json["text"] as? String, let lineCount = json["lineCount"] as? Int {
            // OCR result
            self.resultType = .ocr(text: text, lineCount: lineCount)
        } else if let classifications = json["classifications"] as? [[String: Any]] {
            // Classification result
            let items = classifications.compactMap { item -> (String, Double)? in
                guard let label = item["label"] as? String,
                      let confidence = item["confidence"] as? Double else {
                    return nil
                }
                return (label, confidence)
            }
            self.resultType = .classify(classifications: items)
        } else if let faceCount = json["faceCount"] as? Int {
            // Face detection result
            self.resultType = .detectFaces(faceCount: faceCount)
        } else if let detected = json["documentDetected"] as? Bool {
            // Document detection result
            let confidence = json["confidence"] as? Double ?? 0
            self.resultType = .detectDocument(detected: detected, confidence: confidence)
        } else if let pageCount = json["pageCount"] as? Int {
            // PDF results
            if let text = json["text"] as? String {
                let truncated = json["truncated"] as? Bool ?? false
                if let pagesProcessed = json["pagesProcessed"] as? Int {
                    // PDF OCR
                    self.resultType = .pdfOCR(text: text, pageCount: pageCount, pagesProcessed: pagesProcessed, truncated: truncated)
                } else if let pagesExtracted = json["pagesExtracted"] as? Int {
                    // PDF text extraction
                    self.resultType = .pdfExtract(text: text, pageCount: pageCount, pagesExtracted: pagesExtracted, truncated: truncated)
                } else {
                    return nil
                }
            } else {
                // Just page count
                self.resultType = .pdfPageCount(pageCount: pageCount)
            }
        } else {
            return nil
        }
    }

    @MainActor
    func makeResultView() -> some View {
        ImageAnalysisResultView(result: self)
    }
}

struct ImageAnalysisResultView: View {
    let result: ImageAnalysisResult

    var body: some View {
        switch result.resultType {
        case .ocr(let text, let lineCount):
            ocrView(text: text, lineCount: lineCount)
        case .classify(let classifications):
            classificationView(classifications: classifications)
        case .detectFaces(let faceCount):
            faceDetectionView(faceCount: faceCount)
        case .detectDocument(let detected, let confidence):
            documentDetectionView(detected: detected, confidence: confidence)
        case .pdfExtract(let text, let pageCount, let pagesExtracted, let truncated):
            pdfTextView(text: text, pageCount: pageCount, pagesProcessed: pagesExtracted, truncated: truncated, isOCR: false)
        case .pdfOCR(let text, let pageCount, let pagesProcessed, let truncated):
            pdfTextView(text: text, pageCount: pageCount, pagesProcessed: pagesProcessed, truncated: truncated, isOCR: true)
        case .pdfPageCount(let pageCount):
            pdfPageCountView(pageCount: pageCount)
        }
    }

    @ViewBuilder
    private func ocrView(text: String, lineCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "doc.text.viewfinder")
                    .font(.title3)
                    .foregroundStyle(ClarissaTheme.gradient)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Text Recognition")
                        .font(.subheadline.weight(.medium))
                    Text("\(lineCount) lines extracted")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !text.isEmpty {
                Text(text.prefix(150).trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .padding(.leading, 32)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Text recognition: \(lineCount) lines extracted")
    }

    @ViewBuilder
    private func classificationView(classifications: [(label: String, confidence: Double)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "eye")
                    .font(.title3)
                    .foregroundStyle(ClarissaTheme.gradient)

                Text("Image Classification")
                    .font(.subheadline.weight(.medium))
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(classifications.prefix(3), id: \.label) { item in
                    HStack {
                        Text(item.label.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.caption)
                            .frame(width: 80, alignment: .leading)

                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.secondary.opacity(0.2))
                                    .frame(height: 8)

                                RoundedRectangle(cornerRadius: 2)
                                    .fill(ClarissaTheme.gradient)
                                    .frame(width: geometry.size.width * item.confidence, height: 8)
                            }
                        }
                        .frame(height: 8)

                        Text("\(Int(item.confidence * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 35, alignment: .trailing)
                    }
                }
            }
            .padding(.leading, 32)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Image classification: \(classifications.first?.label ?? "unknown")")
    }

    @ViewBuilder
    private func faceDetectionView(faceCount: Int) -> some View {
        HStack {
            Image(systemName: faceCount > 0 ? "face.smiling" : "face.dashed")
                .font(.title3)
                .foregroundStyle(ClarissaTheme.gradient)

            VStack(alignment: .leading, spacing: 2) {
                Text("Face Detection")
                    .font(.subheadline.weight(.medium))
                Text(faceCount == 0 ? "No faces detected" : "\(faceCount) face\(faceCount == 1 ? "" : "s") detected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Face detection: \(faceCount) faces found")
    }

    @ViewBuilder
    private func documentDetectionView(detected: Bool, confidence: Double) -> some View {
        HStack {
            Image(systemName: detected ? "doc.viewfinder.fill" : "doc.viewfinder")
                .font(.title3)
                .foregroundStyle(ClarissaTheme.gradient)

            VStack(alignment: .leading, spacing: 2) {
                Text("Document Detection")
                    .font(.subheadline.weight(.medium))
                if detected {
                    Text("Document found (\(Int(confidence * 100))% confidence)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No document detected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Document detection: \(detected ? "found" : "not found")")
    }

    @ViewBuilder
    private func pdfTextView(text: String, pageCount: Int, pagesProcessed: Int, truncated: Bool, isOCR: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "doc.richtext")
                    .font(.title3)
                    .foregroundStyle(ClarissaTheme.gradient)

                VStack(alignment: .leading, spacing: 2) {
                    Text(isOCR ? "PDF OCR" : "PDF Text Extract")
                        .font(.subheadline.weight(.medium))

                    HStack(spacing: 8) {
                        Text("\(pagesProcessed) of \(pageCount) pages")
                        if truncated {
                            Text("(truncated)")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if !text.isEmpty {
                Text(text.prefix(150).trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .padding(.leading, 32)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isOCR ? "PDF OCR" : "PDF text"): \(pagesProcessed) pages processed")
    }

    @ViewBuilder
    private func pdfPageCountView(pageCount: Int) -> some View {
        HStack {
            Image(systemName: "doc.on.doc")
                .font(.title3)
                .foregroundStyle(ClarissaTheme.gradient)

            VStack(alignment: .leading, spacing: 2) {
                Text("PDF Info")
                    .font(.subheadline.weight(.medium))
                Text("\(pageCount) page\(pageCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("PDF has \(pageCount) pages")
    }
}

// MARK: - Tool Result View Registry

/// Registry for tool result view types
/// Allows tools to register their custom result display views
/// New tools automatically get rich UI by registering their result type
@MainActor
final class ToolResultViewRegistry {
    /// Shared singleton instance
    static let shared = ToolResultViewRegistry()

    /// Registered parsers keyed by tool name
    /// Since this class is @MainActor, closures don't need @Sendable
    private var parsers: [String: (String) -> AnyToolResult?] = [:]

    private init() {
        // Register built-in result types
        registerBuiltInTypes()
    }

    /// Register a ToolResultDisplayable type for automatic parsing
    /// Call this at app startup to register custom tool result views
    ///
    /// Example:
    /// ```swift
    /// ToolResultViewRegistry.shared.register(WeatherResult.self)
    /// ```
    func register<T: ToolResultDisplayable>(_ type: T.Type) {
        let toolName = T.toolName
        parsers[toolName] = { jsonResult in
            guard let result = T(jsonResult: jsonResult) else {
                return nil
            }
            return AnyToolResult(result)
        }
    }

    /// Parse a tool result into a displayable result
    /// Returns nil if no parser is registered or parsing fails
    func parse(toolName: String, jsonResult: String) -> AnyToolResult? {
        guard let parser = parsers[toolName] else {
            return nil
        }
        return parser(jsonResult)
    }

    /// Check if a tool has a registered result view
    func hasRegisteredView(for toolName: String) -> Bool {
        parsers[toolName] != nil
    }

    /// Get all registered tool names
    var registeredToolNames: [String] {
        Array(parsers.keys).sorted()
    }

    /// Register all built-in tool result types
    private func registerBuiltInTypes() {
        register(WeatherResult.self)
        register(CalendarEventsResult.self)
        register(RemindersResult.self)
        register(CalculatorResult.self)
        register(ContactsResult.self)
        register(LocationResult.self)
        register(RememberResult.self)
        register(WebFetchResult.self)
        register(ImageAnalysisResult.self)
    }
}

// MARK: - Tool Result Parser (Legacy API)

/// Parses tool results and returns the appropriate displayable result
/// This is a convenience wrapper around ToolResultViewRegistry
@MainActor
enum ToolResultParser {
    /// Parse a tool result into a displayable result
    static func parse(toolName: String, jsonResult: String) -> AnyToolResult? {
        ToolResultViewRegistry.shared.parse(toolName: toolName, jsonResult: jsonResult)
    }
}

/// Type-erased wrapper for any tool result
@MainActor
struct AnyToolResult: Sendable {
    private let _makeView: @MainActor @Sendable () -> AnyView

    init<T: ToolResultDisplayable>(_ result: T) {
        self._makeView = { @MainActor in
            AnyView(result.makeResultView())
        }
    }

    func makeView() -> AnyView {
        _makeView()
    }
}

// MARK: - Expandable Tool Result Card

/// An expandable card that shows tool results in the chat
struct ToolResultCard: View {
    let toolName: String
    let displayName: String
    let result: AnyToolResult
    let status: ToolStatus

    @State private var isExpanded = true

    private var statusColor: Color {
        switch status {
        case .running:
            return ClarissaTheme.purple
        case .completed:
            return ClarissaTheme.cyan
        case .failed:
            return .red
        }
    }

    private var statusIcon: String {
        switch status {
        case .running:
            return "circle.dotted"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        }
    }

    private var statusDescription: String {
        switch status {
        case .running:
            return "running"
        case .completed:
            return "completed"
        case .failed:
            return "failed"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header - always visible
            Button {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
                HapticManager.shared.lightTap()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: statusIcon)
                        .foregroundStyle(statusColor)

                    Text(displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(displayName), \(statusDescription)")
            .accessibilityHint(isExpanded ? "Double tap to collapse" : "Double tap to expand")

            // Expandable content
            if isExpanded {
                Divider()
                    .padding(.horizontal, 12)

                result.makeView()
                    .padding(12)
            }
        }
        .background(statusColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(statusColor.opacity(0.2), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }
}

