import Foundation
import WatchKit

/// Manages background app refresh for the Watch app
/// Keeps WatchConnectivity active so the app is ready faster when opened
@MainActor
final class BackgroundTaskManager {
    static let shared = BackgroundTaskManager()

    /// Background task identifier
    private let refreshTaskIdentifier = "dev.rye.clarissa.watchkitapp.refresh"

    /// How often to schedule background refresh (in seconds)
    /// watchOS limits this, but we request every 15 minutes
    private let refreshInterval: TimeInterval = 15 * 60

    private init() {}

    /// Schedule the next background refresh task
    func scheduleBackgroundRefresh() {
        let preferredDate = Date(timeIntervalSinceNow: refreshInterval)

        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: preferredDate,
            userInfo: nil
        ) { error in
            if let error = error {
                print("Failed to schedule background refresh: \(error.localizedDescription)")
            }
        }
    }

    /// Handle a background refresh task
    /// This keeps WatchConnectivity alive and ready
    func handleBackgroundRefresh() async {
        // Ensure WatchConnectivity is activated
        WatchConnectivityClient.shared.activate()

        // Ping iPhone to keep connection warm (if reachable)
        let isReachable = await WatchConnectivityClient.shared.ping()

        if isReachable {
            print("Background refresh: iPhone is reachable")
        }

        // Schedule the next refresh
        scheduleBackgroundRefresh()
    }
}

// MARK: - ExtensionDelegate for Background Tasks

/// Extension delegate to handle background tasks
/// This is used alongside the SwiftUI App lifecycle
final class ExtensionDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        // Schedule initial background refresh
        Task { @MainActor in
            BackgroundTaskManager.shared.scheduleBackgroundRefresh()
        }
    }

    func applicationDidBecomeActive() {
        // Ensure connectivity is active when app becomes active
        Task { @MainActor in
            WatchConnectivityClient.shared.activate()
        }
    }

    func applicationWillResignActive() {
        // Schedule refresh when going to background
        Task { @MainActor in
            BackgroundTaskManager.shared.scheduleBackgroundRefresh()
        }
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            switch task {
            case let backgroundTask as WKApplicationRefreshBackgroundTask:
                // Handle background app refresh
                Task { @MainActor in
                    await BackgroundTaskManager.shared.handleBackgroundRefresh()
                    backgroundTask.setTaskCompletedWithSnapshot(false)
                }

            case let snapshotTask as WKSnapshotRefreshBackgroundTask:
                // Handle snapshot refresh
                snapshotTask.setTaskCompleted(
                    restoredDefaultState: true,
                    estimatedSnapshotExpiration: Date.distantFuture,
                    userInfo: nil
                )

            case let connectivityTask as WKWatchConnectivityRefreshBackgroundTask:
                // Handle WatchConnectivity background task
                // The system wakes us when data arrives from the phone
                Task { @MainActor in
                    WatchConnectivityClient.shared.activate()
                }
                connectivityTask.setTaskCompletedWithSnapshot(false)

            default:
                // Mark any other tasks as complete
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}

