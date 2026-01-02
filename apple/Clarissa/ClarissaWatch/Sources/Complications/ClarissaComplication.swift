import SwiftUI
import WidgetKit

/// Clarissa Watch Complication
/// Provides quick access to Clarissa from the watch face
struct ClarissaComplication: Widget {
    let kind: String = "ClarissaComplication"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClarissaComplicationProvider()) { entry in
            ClarissaComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Clarissa")
        .description("Quick access to your AI assistant")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

// MARK: - Timeline Provider

struct ClarissaComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ClarissaComplicationEntry {
        ClarissaComplicationEntry(date: Date())
    }
    
    func getSnapshot(in context: Context, completion: @escaping (ClarissaComplicationEntry) -> Void) {
        completion(ClarissaComplicationEntry(date: Date()))
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<ClarissaComplicationEntry>) -> Void) {
        // Complications are static - just show the app icon/name
        let entry = ClarissaComplicationEntry(date: Date())
        let timeline = Timeline(entries: [entry], policy: .never)
        completion(timeline)
    }
}

// MARK: - Entry

struct ClarissaComplicationEntry: TimelineEntry {
    let date: Date
}

// MARK: - Views

struct ClarissaComplicationView: View {
    @Environment(\.widgetFamily) var family
    let entry: ClarissaComplicationEntry
    
    var body: some View {
        switch family {
        case .accessoryCircular:
            CircularComplicationView()
        case .accessoryCorner:
            CornerComplicationView()
        case .accessoryRectangular:
            RectangularComplicationView()
        case .accessoryInline:
            InlineComplicationView()
        default:
            CircularComplicationView()
        }
    }
}

/// Circular complication - shows app icon
struct CircularComplicationView: View {
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.title2)
                .foregroundStyle(.primary)
        }
    }
}

/// Corner complication - shows icon with text
struct CornerComplicationView: View {
    var body: some View {
        Image(systemName: "bubble.left.and.bubble.right.fill")
            .font(.title3)
            .widgetLabel {
                Text("Clarissa")
            }
    }
}

/// Rectangular complication - shows name and prompt
struct RectangularComplicationView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.title2)
                .foregroundStyle(.blue)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Clarissa")
                    .font(.headline)
                    .fontWeight(.semibold)
                Text("Tap to ask")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
    }
}

/// Inline complication - shows text only
struct InlineComplicationView: View {
    var body: some View {
        Label("Ask Clarissa", systemImage: "bubble.left.and.bubble.right.fill")
    }
}

// MARK: - Previews

#Preview("Circular", as: .accessoryCircular) {
    ClarissaComplication()
} timeline: {
    ClarissaComplicationEntry(date: Date())
}

#Preview("Corner", as: .accessoryCorner) {
    ClarissaComplication()
} timeline: {
    ClarissaComplicationEntry(date: Date())
}

#Preview("Rectangular", as: .accessoryRectangular) {
    ClarissaComplication()
} timeline: {
    ClarissaComplicationEntry(date: Date())
}

#Preview("Inline", as: .accessoryInline) {
    ClarissaComplication()
} timeline: {
    ClarissaComplicationEntry(date: Date())
}

