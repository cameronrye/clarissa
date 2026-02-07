import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Manages Live Activities during multi-tool ReAct execution
/// Only starts an activity when 2+ tools are called (avoids noise for single tool calls)
@available(iOS 16.1, *)
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    #if canImport(ActivityKit)
    private var currentActivity: Activity<ClarissaActivityAttributes>?
    #endif
    private var completedSteps = 0
    private var totalSteps = 0

    private init() {}

    /// Start a Live Activity for multi-tool execution
    func startActivity(question: String, currentTool: String) {
        #if canImport(ActivityKit) && os(iOS)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = ClarissaActivityAttributes(question: question)
        let state = ClarissaActivityAttributes.ContentState(
            currentTool: currentTool,
            toolStatus: "Running",
            completedSteps: 0,
            totalSteps: 2,
            isProcessing: true
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
            currentActivity = activity
            completedSteps = 0
            totalSteps = 2
        } catch {
            ClarissaLogger.ui.error("Failed to start Live Activity: \(error.localizedDescription)")
        }
        #endif
    }

    /// Update the Live Activity with current tool progress
    func updateTool(name: String, status: String = "Running", planStepNames: [String]? = nil) {
        #if canImport(ActivityKit) && os(iOS)
        guard let activity = currentActivity else { return }

        totalSteps = max(totalSteps, completedSteps + 1)
        let state = ClarissaActivityAttributes.ContentState(
            currentTool: name,
            toolStatus: status,
            completedSteps: completedSteps,
            totalSteps: totalSteps,
            isProcessing: true,
            planStepNames: planStepNames
        )

        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
        #endif
    }

    /// Mark a tool step as completed
    func completeStep() {
        completedSteps += 1
    }

    /// End the Live Activity (agent finished responding)
    func endActivity() {
        #if canImport(ActivityKit) && os(iOS)
        guard let activity = currentActivity else { return }

        let finalState = ClarissaActivityAttributes.ContentState(
            currentTool: "Done",
            toolStatus: "Complete",
            completedSteps: completedSteps,
            totalSteps: completedSteps,
            isProcessing: false
        )

        Task {
            await activity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .after(.now + 5))
        }

        currentActivity = nil
        completedSteps = 0
        totalSteps = 0
        #endif
    }
}
