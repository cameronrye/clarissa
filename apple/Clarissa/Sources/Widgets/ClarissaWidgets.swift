import SwiftUI
import WidgetKit
import AppIntents

// MARK: - Widget Bundle

/// Bundle containing all Clarissa widgets
/// Note: This is intended to be the @main entry for a Widget Extension target
/// For now, widgets are included in the main app target for development
@available(iOS 17.0, macOS 14.0, *)
public struct ClarissaWidgetBundle: WidgetBundle {
    public init() {}

    public var body: some Widget {
        QuickAskWidget()
        ConversationWidget()
        MorningWidget()
        MemorySpotlightWidget()
        #if os(iOS)
        StandByWidget()
        #endif
    }
}

// MARK: - Timeline Entry

struct ClarissaWidgetEntry: TimelineEntry {
    let date: Date
    let lastMessage: String?
    let lastResponse: String?
    let suggestedQuestions: [String]
    
    static var placeholder: ClarissaWidgetEntry {
        ClarissaWidgetEntry(
            date: Date(),
            lastMessage: nil,
            lastResponse: nil,
            suggestedQuestions: WidgetConversationData.defaultQuestions
        )
    }
}

// MARK: - Timeline Provider

struct ClarissaTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> ClarissaWidgetEntry {
        .placeholder
    }
    
    func getSnapshot(in context: Context, completion: @escaping (ClarissaWidgetEntry) -> Void) {
        let entry = loadEntry()
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<ClarissaWidgetEntry>) -> Void) {
        let entry = loadEntry()
        // Refresh every 15 minutes or when app updates data
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
    
    private func loadEntry() -> ClarissaWidgetEntry {
        guard let defaults = ClarissaAppGroup.sharedDefaults else {
            return .placeholder
        }
        
        let lastMessage = defaults.string(forKey: ClarissaAppGroup.lastMessageKey)
        let lastResponse = defaults.string(forKey: ClarissaAppGroup.lastResponseKey)
        
        var suggestedQuestions = WidgetConversationData.defaultQuestions
        if let data = defaults.data(forKey: ClarissaAppGroup.suggestedQuestionsKey),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            suggestedQuestions = decoded
        }
        
        return ClarissaWidgetEntry(
            date: Date(),
            lastMessage: lastMessage,
            lastResponse: lastResponse,
            suggestedQuestions: suggestedQuestions
        )
    }
}

// MARK: - Quick Ask Widget

/// Small widget for quick access to ask Clarissa
@available(iOS 17.0, macOS 14.0, *)
public struct QuickAskWidget: Widget {
    public init() {}

    public let kind = "QuickAskWidget"

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClarissaTimelineProvider()) { entry in
            QuickAskWidgetView(entry: entry)
                .containerBackground(.ultraThinMaterial, for: .widget)
        }
        .configurationDisplayName("Ask Clarissa")
        .description("Quick access to ask a question")
        #if os(iOS)
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular
        ])
        #else
        .supportedFamilies([
            .systemSmall,
            .systemMedium
        ])
        #endif
    }
}

// MARK: - Conversation Widget

/// Medium/Large widget showing recent conversation
@available(iOS 17.0, macOS 14.0, *)
public struct ConversationWidget: Widget {
    public init() {}

    public let kind = "ConversationWidget"

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClarissaTimelineProvider()) { entry in
            ConversationWidgetView(entry: entry)
                .containerBackground(.ultraThinMaterial, for: .widget)
        }
        .configurationDisplayName("Recent Conversation")
        .description("See your last conversation and continue")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - Widget Theme Colors

/// Theme colors for widgets (matches main app ClarissaTheme)
enum WidgetTheme {
    static let pink = Color(red: 0.925, green: 0.286, blue: 0.600)
    static let purple = Color(red: 0.545, green: 0.361, blue: 0.965)
    static let cyan = Color(red: 0.024, green: 0.714, blue: 0.831)

    static let gradient = LinearGradient(
        colors: [pink, purple, cyan],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Morning Widget

/// Timeline entry for morning briefing data
struct MorningWidgetEntry: TimelineEntry {
    let date: Date
    let weather: String?
    let nextEvent: String?
    let nextEventTime: Date?
    let topReminder: String?
    let lastUpdated: Date?

    static var placeholder: MorningWidgetEntry {
        MorningWidgetEntry(
            date: Date(),
            weather: "72°F, Sunny",
            nextEvent: "Team standup",
            nextEventTime: Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date()),
            topReminder: "Buy groceries",
            lastUpdated: Date()
        )
    }
}

/// Timeline provider for morning widget — refreshes at morning hours, then every 2 hours
struct MorningTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> MorningWidgetEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (MorningWidgetEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MorningWidgetEntry>) -> Void) {
        let entry = loadEntry()
        // Refresh every 2 hours
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 2, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func loadEntry() -> MorningWidgetEntry {
        guard let defaults = ClarissaAppGroup.sharedDefaults,
              let data = defaults.data(forKey: ClarissaAppGroup.morningDataKey),
              let morning = try? JSONDecoder().decode(WidgetMorningData.self, from: data) else {
            return MorningWidgetEntry(
                date: Date(), weather: nil, nextEvent: nil,
                nextEventTime: nil, topReminder: nil, lastUpdated: nil
            )
        }

        return MorningWidgetEntry(
            date: Date(),
            weather: morning.weatherSummary,
            nextEvent: morning.nextEvent,
            nextEventTime: morning.nextEventTime,
            topReminder: morning.topReminder,
            lastUpdated: morning.lastUpdated
        )
    }
}

/// Large widget showing today's weather, next event, and top reminder
@available(iOS 17.0, macOS 14.0, *)
public struct MorningWidget: Widget {
    public init() {}
    public let kind = "MorningWidget"

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MorningTimelineProvider()) { entry in
            MorningWidgetView(entry: entry)
                .containerBackground(.ultraThinMaterial, for: .widget)
        }
        .configurationDisplayName("Morning Briefing")
        .description("Today's weather, next event, and top reminder at a glance")
        .supportedFamilies([.systemLarge])
    }
}

/// View for the morning briefing widget
struct MorningWidgetView: View {
    let entry: MorningWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(WidgetTheme.gradient)
                Text("Good \(timeOfDayGreeting)")
                    .font(.headline)
                Spacer()
            }

            if entry.weather == nil && entry.nextEvent == nil && entry.topReminder == nil {
                Spacer()
                Text("Open Clarissa to set up your morning briefing")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                // Weather row
                if let weather = entry.weather {
                    HStack(spacing: 12) {
                        Image(systemName: "cloud.sun.fill")
                            .font(.title2)
                            .foregroundStyle(.orange)
                            .frame(width: 32)
                        VStack(alignment: .leading) {
                            Text("Weather")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(weather)
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        Spacer()
                    }
                }

                // Calendar row
                if let event = entry.nextEvent {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar")
                            .font(.title2)
                            .foregroundStyle(WidgetTheme.purple)
                            .frame(width: 32)
                        VStack(alignment: .leading) {
                            Text("Next Up")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(event)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            if let time = entry.nextEventTime {
                                Text(time, style: .time)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                }

                // Reminder row
                if let reminder = entry.topReminder {
                    HStack(spacing: 12) {
                        Image(systemName: "checklist")
                            .font(.title2)
                            .foregroundStyle(WidgetTheme.cyan)
                            .frame(width: 32)
                        VStack(alignment: .leading) {
                            Text("Reminder")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(reminder)
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        Spacer()
                    }
                }

                Spacer(minLength: 0)

                // Staleness indicator
                if let lastUpdated = entry.lastUpdated,
                   Date().timeIntervalSince(lastUpdated) > 3600 {
                    Text("Updated \(lastUpdated, style: .relative) ago")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding()
    }

    private var timeOfDayGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12: return "morning"
        case 12..<17: return "afternoon"
        default: return "evening"
        }
    }
}

// MARK: - Memory Spotlight Widget

/// Timeline entry for memory spotlight
struct MemorySpotlightEntry: TimelineEntry {
    let date: Date
    let memoryContent: String?
    let topics: [String]?
    let reason: String?

    static var placeholder: MemorySpotlightEntry {
        MemorySpotlightEntry(
            date: Date(),
            memoryContent: "You prefer dark roast coffee in the morning",
            topics: ["coffee", "preferences"],
            reason: "Part of your morning routine"
        )
    }
}

/// Timeline provider for memory spotlight — refreshes every 4 hours
struct MemorySpotlightTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> MemorySpotlightEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (MemorySpotlightEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MemorySpotlightEntry>) -> Void) {
        let entry = loadEntry()
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 4, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func loadEntry() -> MemorySpotlightEntry {
        guard let defaults = ClarissaAppGroup.sharedDefaults,
              let data = defaults.data(forKey: ClarissaAppGroup.memorySpotlightKey),
              let spotlight = try? JSONDecoder().decode(WidgetMemorySpotlight.self, from: data) else {
            return MemorySpotlightEntry(date: Date(), memoryContent: nil, topics: nil, reason: nil)
        }

        return MemorySpotlightEntry(
            date: Date(),
            memoryContent: spotlight.memoryContent,
            topics: spotlight.memoryTopics,
            reason: spotlight.reason
        )
    }
}

/// Medium widget surfacing a relevant memory
@available(iOS 17.0, macOS 14.0, *)
public struct MemorySpotlightWidget: Widget {
    public init() {}
    public let kind = "MemorySpotlightWidget"

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MemorySpotlightTimelineProvider()) { entry in
            MemorySpotlightWidgetView(entry: entry)
                .containerBackground(.ultraThinMaterial, for: .widget)
        }
        .configurationDisplayName("Memory Spotlight")
        .description("A relevant memory surfaced based on context")
        .supportedFamilies([.systemMedium])
    }
}

/// View for the memory spotlight widget
struct MemorySpotlightWidgetView: View {
    let entry: MemorySpotlightEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(WidgetTheme.gradient)
                Text("Memory")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if let content = entry.memoryContent {
                Text(content)
                    .font(.subheadline)
                    .lineLimit(3)

                if let reason = entry.reason, !reason.isEmpty {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .italic()
                }

                if let topics = entry.topics, !topics.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(topics.prefix(3), id: \.self) { topic in
                            Text(topic)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(WidgetTheme.purple.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                }
            } else {
                Text("Open Clarissa and save some memories to see them here")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding()
    }
}

// MARK: - StandBy Widget

#if os(iOS)
/// Timeline entry for StandBy mode
struct StandByWidgetEntry: TimelineEntry {
    let date: Date
    let weather: String?
    let nextEvent: String?
    let nextEventTime: Date?
    let topReminder: String?
    let memoryContent: String?

    static var placeholder: StandByWidgetEntry {
        StandByWidgetEntry(
            date: Date(),
            weather: "72°F, Sunny",
            nextEvent: "Team standup",
            nextEventTime: Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date()),
            topReminder: "Buy groceries",
            memoryContent: "You prefer dark roast coffee"
        )
    }
}

/// Timeline provider for StandBy — combines morning + memory data
struct StandByTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> StandByWidgetEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (StandByWidgetEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StandByWidgetEntry>) -> Void) {
        let entry = loadEntry()
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 2, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func loadEntry() -> StandByWidgetEntry {
        let defaults = ClarissaAppGroup.sharedDefaults

        var weather: String?
        var nextEvent: String?
        var nextEventTime: Date?
        var topReminder: String?
        var memoryContent: String?

        if let data = defaults?.data(forKey: ClarissaAppGroup.morningDataKey),
           let morning = try? JSONDecoder().decode(WidgetMorningData.self, from: data) {
            weather = morning.weatherSummary
            nextEvent = morning.nextEvent
            nextEventTime = morning.nextEventTime
            topReminder = morning.topReminder
        }

        if let data = defaults?.data(forKey: ClarissaAppGroup.memorySpotlightKey),
           let spotlight = try? JSONDecoder().decode(WidgetMemorySpotlight.self, from: data) {
            memoryContent = spotlight.memoryContent
        }

        return StandByWidgetEntry(
            date: Date(),
            weather: weather,
            nextEvent: nextEvent,
            nextEventTime: nextEventTime,
            topReminder: topReminder,
            memoryContent: memoryContent
        )
    }
}

/// Full-screen StandBy display with rotating contextual info
@available(iOS 17.0, *)
public struct StandByWidget: Widget {
    public init() {}
    public let kind = "StandByWidget"

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StandByTimelineProvider()) { entry in
            StandByWidgetView(entry: entry)
                .containerBackground(.ultraThinMaterial, for: .widget)
        }
        .configurationDisplayName("Clarissa StandBy")
        .description("Contextual info for StandBy mode")
        .supportedFamilies([.systemExtraLarge])
    }
}

/// View for the StandBy widget
struct StandByWidgetView: View {
    let entry: StandByWidgetEntry

    var body: some View {
        VStack(spacing: 24) {
            // Branding
            HStack {
                Image(systemName: "sparkles")
                    .font(.title)
                    .foregroundStyle(WidgetTheme.gradient)
                Text("Clarissa")
                    .font(.title2)
                    .fontWeight(.bold)
            }

            Spacer()

            // Content cards
            VStack(spacing: 16) {
                if let weather = entry.weather {
                    infoCard(icon: "cloud.sun.fill", iconColor: .orange, label: "Weather", value: weather)
                }

                if let event = entry.nextEvent {
                    let timeStr = entry.nextEventTime.map { time in
                        let formatter = DateFormatter()
                        formatter.timeStyle = .short
                        return " at " + formatter.string(from: time)
                    } ?? ""
                    infoCard(icon: "calendar", iconColor: WidgetTheme.purple, label: "Next Up", value: event + timeStr)
                }

                if let reminder = entry.topReminder {
                    infoCard(icon: "checklist", iconColor: WidgetTheme.cyan, label: "Reminder", value: reminder)
                }

                if let memory = entry.memoryContent {
                    infoCard(icon: "brain.head.profile", iconColor: WidgetTheme.pink, label: "Memory", value: memory)
                }
            }

            Spacer()
        }
        .padding(24)
    }

    private func infoCard(icon: String, iconColor: Color, label: String, value: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(iconColor)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
#endif

