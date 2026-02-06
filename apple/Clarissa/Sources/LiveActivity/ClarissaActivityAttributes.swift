import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// Activity attributes for Live Activities during multi-tool ReAct execution
/// Shows progress on Lock Screen and Dynamic Island when the agent is running multiple tools
@available(iOS 16.1, *)
struct ClarissaActivityAttributes: ActivityAttributes {
    /// Static context that doesn't change during the activity
    struct ContentState: Codable, Hashable {
        /// The current tool being executed
        var currentTool: String

        /// Status of the current tool
        var toolStatus: String

        /// Number of completed steps
        var completedSteps: Int

        /// Total expected steps (estimated)
        var totalSteps: Int

        /// Whether the activity is still in progress
        var isProcessing: Bool
    }

    /// The user's original question
    var question: String
}
#endif
