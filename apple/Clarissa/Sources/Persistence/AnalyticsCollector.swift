import Foundation
import os.log

/// Privacy-respecting on-device analytics — no data leaves the device.
/// Tracks tool failure rates, ReAct loop iterations, context budget utilization,
/// and crash-free session rate for the Settings diagnostics panel.
actor AnalyticsCollector {
    static let shared = AnalyticsCollector()

    private static let logger = Logger(subsystem: "dev.rye.Clarissa", category: "Analytics")

    // MARK: - Data Models

    /// Metrics for a single agent session (one user query → response cycle)
    struct SessionMetrics: Codable, Sendable {
        let sessionId: UUID
        let date: Date
        var toolCalls: Int = 0
        var toolFailures: Int = 0
        var reactLoopIterations: Int = 0
        var contextBudgetUsagePercent: Double = 0
        var failedToolNames: [String] = []
        var durationSeconds: TimeInterval = 0
    }

    /// Aggregated metrics over a rolling window for display in Settings
    struct AggregateMetrics: Codable, Sendable {
        var totalSessions: Int = 0
        var crashFreeSessions: Int = 0
        var totalToolCalls: Int = 0
        var totalToolFailures: Int = 0
        var totalReactIterations: Int = 0
        var totalContextUsageSum: Double = 0
        var lastUpdated: Date = Date()

        /// Average tool success rate (0.0–1.0)
        var toolSuccessRate: Double {
            guard totalToolCalls > 0 else { return 1.0 }
            return 1.0 - (Double(totalToolFailures) / Double(totalToolCalls))
        }

        /// Average ReAct loop iterations per session
        var avgReactIterations: Double {
            guard totalSessions > 0 else { return 0 }
            return Double(totalReactIterations) / Double(totalSessions)
        }

        /// Average context budget utilization (0.0–1.0)
        var avgContextUtilization: Double {
            guard totalSessions > 0 else { return 0 }
            return totalContextUsageSum / Double(totalSessions)
        }

        /// Crash-free session rate (0.0–1.0)
        var crashFreeRate: Double {
            guard totalSessions > 0 else { return 1.0 }
            return Double(crashFreeSessions) / Double(totalSessions)
        }
    }

    // MARK: - Storage

    private static let storageKey = "clarissa_analytics"
    private static let rollingWindowDays = 30

    private var currentSession: SessionMetrics?
    private var aggregate: AggregateMetrics = AggregateMetrics()
    private var isLoaded = false

    private init() {}

    // MARK: - Session Lifecycle

    /// Start tracking a new agent session
    func beginSession() {
        ensureLoaded()
        currentSession = SessionMetrics(sessionId: UUID(), date: Date())
    }

    /// Record a tool call (success or failure)
    func recordToolCall(name: String, success: Bool) {
        ensureLoaded()
        guard currentSession != nil else {
            Self.logger.warning("recordToolCall called without active session")
            return
        }
        currentSession?.toolCalls += 1
        if !success {
            currentSession?.toolFailures += 1
            currentSession?.failedToolNames.append(name)
        }
    }

    /// Record one ReAct loop iteration
    func recordReactIteration() {
        ensureLoaded()
        currentSession?.reactLoopIterations += 1
    }

    /// Record the current context budget utilization (0.0–1.0)
    func recordContextUsage(percent: Double) {
        ensureLoaded()
        currentSession?.contextBudgetUsagePercent = percent
    }

    /// Complete the current session (call when agent.run() finishes)
    func completeSession(crashed: Bool = false) {
        ensureLoaded()

        guard var session = currentSession else { return }
        session.durationSeconds = Date().timeIntervalSince(session.date)

        // Merge into aggregate
        aggregate.totalSessions += 1
        if !crashed {
            aggregate.crashFreeSessions += 1
        }
        aggregate.totalToolCalls += session.toolCalls
        aggregate.totalToolFailures += session.toolFailures
        aggregate.totalReactIterations += session.reactLoopIterations
        aggregate.totalContextUsageSum += session.contextBudgetUsagePercent
        aggregate.lastUpdated = Date()

        currentSession = nil
        save()

        let tools = session.toolCalls
        let failures = session.toolFailures
        let iterations = session.reactLoopIterations
        Self.logger.info("Session complete: \(tools) tools (\(failures) failed), \(iterations) iterations")
    }

    // MARK: - Queries

    /// Get the aggregate metrics for Settings display
    func getAggregateMetrics() -> AggregateMetrics {
        ensureLoaded()
        return aggregate
    }

    /// Reset all analytics (for privacy/testing)
    func reset() {
        aggregate = AggregateMetrics()
        currentSession = nil
        save()
    }

    // MARK: - Persistence

    private func ensureLoaded() {
        guard !isLoaded else { return }
        load()
        isLoaded = true
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else { return }
        do {
            aggregate = try JSONDecoder().decode(AggregateMetrics.self, from: data)

            // Prune if data is older than rolling window
            if let cutoff = Calendar.current.date(byAdding: .day, value: -Self.rollingWindowDays, to: Date()),
               aggregate.lastUpdated < cutoff {
                Self.logger.info("Analytics data older than \(Self.rollingWindowDays) days, resetting")
                aggregate = AggregateMetrics()
            }
        } catch {
            Self.logger.warning("Failed to decode analytics: \(error.localizedDescription)")
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(aggregate)
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        } catch {
            Self.logger.warning("Failed to save analytics: \(error.localizedDescription)")
        }
    }
}
