import SwiftUI
#if canImport(FoundationModels)
import FoundationModels

// MARK: - Streaming Partial Generation Views
//
// These views demonstrate PartiallyGenerated types for responsive streaming UI.
// Properties appear progressively as they're decoded, providing better UX than raw token streaming.

/// View that displays streaming conversation analysis with progressive updates
@available(iOS 26.0, macOS 26.0, *)
struct StreamingAnalysisView: View {
    let partial: ConversationAnalysis.PartiallyGenerated?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title appears first (ordered for optimal streaming)
            if let title = partial?.title {
                HStack {
                    Image(systemName: "text.quote")
                        .foregroundStyle(ClarissaTheme.purple)
                    Text(title)
                        .font(.headline)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Summary appears next
            if let summary = partial?.summary {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }

            // Topics stream in as array
            if let topics = partial?.topics, !topics.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(topics, id: \.self) { topic in
                        TopicChip(topic: topic)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }

            // Sentiment and category appear last
            HStack(spacing: 16) {
                if let sentiment = partial?.sentiment {
                    Label(sentiment.capitalized, systemImage: sentimentIcon(sentiment))
                        .font(.caption)
                        .foregroundStyle(sentimentColor(sentiment))
                        .transition(.opacity)
                }

                if let category = partial?.category {
                    Label(category.capitalized, systemImage: categoryIcon(category))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
        }
        .animation(.smooth, value: partial?.title)
        .animation(.smooth, value: partial?.summary)
        .animation(.smooth, value: partial?.topics?.count)
        .animation(.smooth, value: partial?.sentiment)
        .animation(.smooth, value: partial?.category)
    }

    private func sentimentIcon(_ sentiment: String) -> String {
        switch sentiment.lowercased() {
        case "positive": return "face.smiling"
        case "negative": return "face.dashed"
        default: return "minus.circle"
        }
    }

    private func sentimentColor(_ sentiment: String) -> Color {
        switch sentiment.lowercased() {
        case "positive": return .green
        case "negative": return .red
        default: return .secondary
        }
    }

    private func categoryIcon(_ category: String) -> String {
        switch category.lowercased() {
        case "technical": return "wrench.and.screwdriver"
        case "creative": return "paintbrush"
        case "task": return "checklist"
        case "social": return "person.2"
        default: return "info.circle"
        }
    }
}

/// View that displays streaming action items with progressive updates
@available(iOS 26.0, macOS 26.0, *)
struct StreamingActionItemsView: View {
    let partial: ActionItems.PartiallyGenerated?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Tasks stream in progressively
            if let tasks = partial?.tasks, !tasks.isEmpty {
                Section {
                    ForEach(Array(tasks.enumerated()), id: \.offset) { _, task in
                        TaskRow(task: task)
                            .transition(.asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                } header: {
                    Label("Tasks", systemImage: "checklist")
                        .font(.subheadline.bold())
                }
            }

            // Events stream in
            if let events = partial?.events, !events.isEmpty {
                Section {
                    ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                        EventRow(event: event)
                            .transition(.opacity)
                    }
                } header: {
                    Label("Events", systemImage: "calendar")
                        .font(.subheadline.bold())
                }
            }

            // Reminders stream in
            if let reminders = partial?.reminders, !reminders.isEmpty {
                Section {
                    ForEach(Array(reminders.enumerated()), id: \.offset) { _, reminder in
                        ReminderRow(reminder: reminder)
                            .transition(.opacity)
                    }
                } header: {
                    Label("Reminders", systemImage: "bell")
                        .font(.subheadline.bold())
                }
            }
        }
        .animation(.smooth, value: partial?.tasks?.count)
        .animation(.smooth, value: partial?.events?.count)
        .animation(.smooth, value: partial?.reminders?.count)
    }
}

// MARK: - Helper Views

/// Chip view for displaying a topic tag
@available(iOS 26.0, macOS 26.0, *)
private struct TopicChip: View {
    let topic: String

    var body: some View {
        Text(topic)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(ClarissaTheme.purple.opacity(0.15))
            .foregroundStyle(ClarissaTheme.purple)
            .clipShape(Capsule())
    }
}

/// Row view for a task
@available(iOS 26.0, macOS 26.0, *)
private struct TaskRow: View {
    let task: ActionTask.PartiallyGenerated

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                if let title = task.title {
                    Text(title)
                        .font(.subheadline)
                }

                HStack(spacing: 8) {
                    if let priority = task.priority {
                        Text(priority.capitalized)
                            .font(.caption2)
                            .foregroundStyle(priorityColor(priority))
                    }
                    if let dueDate = task.dueDate {
                        Text(dueDate)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let assignee = task.assignee {
                        Text("@\(assignee)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func priorityColor(_ priority: String) -> Color {
        switch priority.lowercased() {
        case "high": return .red
        case "medium": return .orange
        default: return .secondary
        }
    }
}

/// Row view for an event
@available(iOS 26.0, macOS 26.0, *)
private struct EventRow: View {
    let event: ExtractedEvent.PartiallyGenerated

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "calendar.badge.plus")
                .font(.caption)
                .foregroundStyle(ClarissaTheme.purple)

            VStack(alignment: .leading, spacing: 2) {
                if let title = event.title {
                    Text(title)
                        .font(.subheadline)
                }

                HStack(spacing: 8) {
                    if let startDate = event.startDate {
                        Text(startDate)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let location = event.location {
                        Label(location, systemImage: "location")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

/// Row view for a reminder
@available(iOS 26.0, macOS 26.0, *)
private struct ReminderRow: View {
    let reminder: ExtractedReminder.PartiallyGenerated

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "bell.badge")
                .font(.caption)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                if let title = reminder.title {
                    Text(title)
                        .font(.subheadline)
                }

                HStack(spacing: 8) {
                    if let dueDate = reminder.dueDate {
                        Text(dueDate)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let notes = reminder.notes {
                        Text(notes)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

// MARK: - Flow Layout

/// A simple flow layout for wrapping content horizontally
@available(iOS 26.0, macOS 26.0, *)
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            totalHeight = currentY + lineHeight
        }

        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}

#endif
