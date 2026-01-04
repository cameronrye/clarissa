import SwiftUI
import WidgetKit
import AppIntents

// MARK: - Quick Ask Widget View

@available(iOS 17.0, macOS 14.0, *)
struct QuickAskWidgetView: View {
    let entry: ClarissaWidgetEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        #if os(iOS)
        switch family {
        case .accessoryCircular:
            accessoryCircularView
        case .accessoryRectangular:
            accessoryRectangularView
        case .systemSmall:
            smallView
        case .systemMedium:
            mediumQuickAskView
        default:
            smallView
        }
        #else
        switch family {
        case .systemSmall:
            smallView
        case .systemMedium:
            mediumQuickAskView
        default:
            smallView
        }
        #endif
    }

    #if os(iOS)
    // MARK: - Lock Screen Circular

    private var accessoryCircularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "sparkles")
                .font(.title2)
        }
        .widgetURL(URL(string: "clarissa://new"))
    }

    // MARK: - Lock Screen Rectangular

    private var accessoryRectangularView: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Clarissa")
                    .font(.headline)
                Text("Tap to ask")
                    .font(.caption)
                    .opacity(0.7)
            }
            Spacer()
        }
        .widgetURL(URL(string: "clarissa://new"))
    }
    #endif
    
    // MARK: - System Small

    private var smallView: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(WidgetTheme.gradient)

            Text("Ask Clarissa")
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: "clarissa://new"))
    }

    // MARK: - System Medium

    private var mediumQuickAskView: some View {
        HStack(spacing: 16) {
            // Left: Logo and title
            VStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 32))
                    .foregroundStyle(WidgetTheme.gradient)

                Text("Clarissa")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            .frame(width: 80)

            // Right: Quick suggestions
            VStack(alignment: .leading, spacing: 6) {
                ForEach(entry.suggestedQuestions.prefix(3), id: \.self) { question in
                    Link(destination: URL(string: "clarissa://ask?q=\(question.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")!) {
                        HStack {
                            Text(question)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
    }
}

// MARK: - Conversation Widget View

@available(iOS 17.0, macOS 14.0, *)
struct ConversationWidgetView: View {
    let entry: ClarissaWidgetEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(WidgetTheme.gradient)
                Text("Clarissa")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                if entry.lastMessage != nil {
                    Text("Continue")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let lastMessage = entry.lastMessage, let lastResponse = entry.lastResponse {
                // Show last conversation
                conversationView(message: lastMessage, response: lastResponse)
            } else {
                // Empty state with suggestions
                emptyStateView
            }
        }
        .padding()
        .widgetURL(URL(string: "clarissa://new"))
    }

    @ViewBuilder
    private func conversationView(message: String, response: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // User message
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "person.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(family == .systemLarge ? 2 : 1)
            }

            // Assistant response
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(WidgetTheme.purple)
                Text(response)
                    .font(.caption)
                    .lineLimit(family == .systemLarge ? 4 : 2)
                    .foregroundStyle(.secondary)
            }
        }

        Spacer()
    }

    private var emptyStateView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Try asking:")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(entry.suggestedQuestions.prefix(family == .systemLarge ? 4 : 2), id: \.self) { question in
                Link(destination: URL(string: "clarissa://ask?q=\(question.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")!) {
                    HStack {
                        Text(question)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "arrow.right.circle")
                            .font(.caption)
                            .foregroundStyle(WidgetTheme.purple)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
    }
}

// MARK: - Widget Previews

@available(iOS 17.0, macOS 14.0, *)
#Preview("Quick Ask - Small", as: .systemSmall) {
    QuickAskWidget()
} timeline: {
    ClarissaWidgetEntry.placeholder
}

@available(iOS 17.0, macOS 14.0, *)
#Preview("Quick Ask - Medium", as: .systemMedium) {
    QuickAskWidget()
} timeline: {
    ClarissaWidgetEntry.placeholder
}

@available(iOS 17.0, macOS 14.0, *)
#Preview("Conversation - Medium", as: .systemMedium) {
    ConversationWidget()
} timeline: {
    ClarissaWidgetEntry(
        date: Date(),
        lastMessage: "What's the weather today?",
        lastResponse: "It's currently 72 degrees and sunny in San Francisco.",
        suggestedQuestions: WidgetConversationData.defaultQuestions
    )
}

@available(iOS 17.0, macOS 14.0, *)
#Preview("Conversation - Large", as: .systemLarge) {
    ConversationWidget()
} timeline: {
    ClarissaWidgetEntry(
        date: Date(),
        lastMessage: "What's on my calendar this week?",
        lastResponse: "You have 5 meetings scheduled this week. The next one is 'Team Standup' tomorrow at 10:00 AM.",
        suggestedQuestions: WidgetConversationData.defaultQuestions
    )
}

