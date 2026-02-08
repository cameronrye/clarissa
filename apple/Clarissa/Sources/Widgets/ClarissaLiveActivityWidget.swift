import SwiftUI
import WidgetKit
#if canImport(ActivityKit) && os(iOS)
import ActivityKit

/// Live Activity widget for showing multi-tool ReAct execution progress
/// Displays on Lock Screen and Dynamic Island during complex agent operations
@available(iOS 16.1, *)
public struct ClarissaLiveActivityWidget: Widget {
    public init() {}
    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: ClarissaActivityAttributes.self) { context in
            // Lock Screen banner
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded view
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.purple)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.completedSteps)/\(context.state.totalSteps)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.currentTool)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(
                        value: Double(context.state.completedSteps),
                        total: Double(max(context.state.totalSteps, 1))
                    )
                    .tint(.purple)
                }
            } compactLeading: {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
            } compactTrailing: {
                Text("\(context.state.completedSteps)/\(context.state.totalSteps)")
                    .font(.caption2)
            } minimal: {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
            }
        }
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<ClarissaActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                Text("Clarissa")
                    .font(.headline)
                Spacer()
                if context.state.isProcessing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            Text(context.state.currentTool)
                .font(.subheadline)

            ProgressView(
                value: Double(context.state.completedSteps),
                total: Double(max(context.state.totalSteps, 1))
            )
            .tint(.purple)
        }
        .padding()
    }
}
#endif
