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

