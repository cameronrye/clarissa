import Foundation
import BackgroundTasks
import os

// MARK: - Scheduled Check-In Model

/// A user-configured schedule that triggers a tool chain or template in the background
/// and delivers results as a local notification.
struct ScheduledCheckIn: Codable, Identifiable, Sendable {
    let id: String
    var name: String
    var isEnabled: Bool

    /// What to run: either a tool chain ID or a conversation template ID
    var triggerType: TriggerType

    /// Schedule configuration
    var schedule: Schedule

    /// When this check-in last ran successfully
    var lastRunAt: Date?

    enum TriggerType: Codable, Sendable {
        case toolChain(chainId: String)
        case template(templateId: String)
    }

    struct Schedule: Codable, Sendable {
        var hour: Int       // 0-23
        var minute: Int     // 0-59
        var days: Set<Weekday>  // Which days of the week

        /// Next fire date from now
        func nextFireDate(after date: Date = Date()) -> Date? {
            let calendar = Calendar.current
            let now = date

            // Try today first, then upcoming days
            for dayOffset in 0..<8 {
                guard let candidateDate = calendar.date(byAdding: .day, value: dayOffset, to: now) else { continue }
                let weekday = calendar.component(.weekday, from: candidateDate)

                guard let clarissaWeekday = Weekday(calendarWeekday: weekday),
                      days.contains(clarissaWeekday) else { continue }

                var components = calendar.dateComponents([.year, .month, .day], from: candidateDate)
                components.hour = hour
                components.minute = minute

                if let fireDate = calendar.date(from: components), fireDate > now {
                    return fireDate
                }
            }
            return nil
        }
    }

    enum Weekday: Int, Codable, CaseIterable, Sendable {
        case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

        var shortName: String {
            switch self {
            case .sunday: return "Sun"
            case .monday: return "Mon"
            case .tuesday: return "Tue"
            case .wednesday: return "Wed"
            case .thursday: return "Thu"
            case .friday: return "Fri"
            case .saturday: return "Sat"
            }
        }

        init?(calendarWeekday: Int) {
            self.init(rawValue: calendarWeekday)
        }
    }
}

// MARK: - Check-In Store

/// Persists scheduled check-ins
actor ScheduledCheckInStore {
    static let shared = ScheduledCheckInStore()

    private let fileName = "scheduled_checkins.json"

    private var fileURL: URL {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        }
        return docs.appendingPathComponent(fileName)
    }

    func load() -> [ScheduledCheckIn] {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let checkIns = try? JSONDecoder().decode([ScheduledCheckIn].self, from: data) else {
            return []
        }
        return checkIns
    }

    func save(_ checkIns: [ScheduledCheckIn]) throws {
        let data = try JSONEncoder().encode(checkIns)
        let url = fileURL
        let dir = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try data.write(to: url, options: .atomic)
    }

    func add(_ checkIn: ScheduledCheckIn) throws {
        var checkIns = load()
        checkIns.append(checkIn)
        try save(checkIns)
    }

    func delete(id: String) throws {
        var checkIns = load()
        checkIns.removeAll { $0.id == id }
        try save(checkIns)
    }

    func update(_ checkIn: ScheduledCheckIn) throws {
        var checkIns = load()
        guard let index = checkIns.firstIndex(where: { $0.id == checkIn.id }) else { return }
        checkIns[index] = checkIn
        try save(checkIns)
    }

    func markRun(id: String) throws {
        var checkIns = load()
        guard let index = checkIns.firstIndex(where: { $0.id == id }) else { return }
        checkIns[index].lastRunAt = Date()
        try save(checkIns)
    }
}

// MARK: - Background Task Scheduler

/// Manages BGTaskScheduler registration and execution for scheduled check-ins
#if os(iOS)
@MainActor
public final class CheckInScheduler {
    public static let shared = CheckInScheduler()

    static let taskIdentifier = "dev.rye.clarissa.checkin"

    private init() {}

    /// Register the background task handler (call from app launch)
    public func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { task in
            Task { @MainActor in
                guard let refreshTask = task as? BGAppRefreshTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                await self.handleBackgroundTask(refreshTask)
            }
        }
    }

    /// Schedule the next background refresh
    public func scheduleNextRun() async {
        let checkIns = await ScheduledCheckInStore.shared.load()
        let enabledCheckIns = checkIns.filter(\.isEnabled)

        guard !enabledCheckIns.isEmpty else { return }

        // Find the earliest next fire date
        let nextDate = enabledCheckIns
            .compactMap { $0.schedule.nextFireDate() }
            .min()

        guard let nextDate else { return }

        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = nextDate

        do {
            try BGTaskScheduler.shared.submit(request)
            ClarissaLogger.notifications.info("Scheduled next check-in at \(nextDate)")
        } catch {
            ClarissaLogger.notifications.error("Failed to schedule background task: \(error.localizedDescription)")
        }
    }

    /// Handle a background task execution
    private func handleBackgroundTask(_ task: BGAppRefreshTask) async {
        // Schedule the next occurrence before running
        await scheduleNextRun()

        let checkIns = await ScheduledCheckInStore.shared.load()
        let now = Date()

        // Find check-ins that should fire now (within a 15-min window)
        let dueCheckIns = checkIns.filter { checkIn in
            guard checkIn.isEnabled else { return false }
            guard let nextFire = checkIn.schedule.nextFireDate(after: now.addingTimeInterval(-900)) else {
                return false
            }
            return nextFire <= now
        }

        // Guard against double-completion (expiration handler vs normal completion)
        let didComplete = OSAllocatedUnfairLock(initialState: false)

        // Set up expiration handler — must call setTaskCompleted
        task.expirationHandler = {
            ClarissaLogger.notifications.info("Background check-in task expired")
            if !didComplete.withLock({ let v = $0; $0 = true; return v }) {
                task.setTaskCompleted(success: false)
            }
        }

        // Execute each due check-in (check cancellation between iterations)
        for checkIn in dueCheckIns {
            guard !Task.isCancelled else { break }
            do {
                let result = try await executeCheckIn(checkIn)
                try await ScheduledCheckInStore.shared.markRun(id: checkIn.id)

                // Deliver notification with result
                NotificationManager.shared.scheduleCheckInNotification(
                    title: checkIn.name,
                    body: result,
                    checkInId: checkIn.id,
                    at: Date()  // Deliver immediately
                )
            } catch {
                ClarissaLogger.notifications.error("Check-in '\(checkIn.name)' failed: \(error.localizedDescription)")
            }
        }

        if !didComplete.withLock({ let v = $0; $0 = true; return v }) {
            task.setTaskCompleted(success: true)
        }
    }

    /// Execute a single check-in and return the summary text
    private func executeCheckIn(_ checkIn: ScheduledCheckIn) async throws -> String {
        switch checkIn.triggerType {
        case .toolChain(let chainId):
            let chains = await ToolChain.allChains()
            guard let chain = chains.first(where: { $0.id == chainId }) else {
                throw ToolError.notAvailable("Chain '\(chainId)' not found")
            }

            let executor = ToolChainExecutor()
            let result = try await executor.execute(chain: chain)
            return result.synthesisContext

        case .template(let templateId):
            let templates = await ConversationTemplate.allTemplates()
            guard let template = templates.first(where: { $0.id == templateId }) else {
                throw ToolError.notAvailable("Template '\(templateId)' not found")
            }

            // Execute template's initial prompt through a lightweight agent
            let agent = Agent()
            #if canImport(FoundationModels)
            if #available(iOS 26.0, macOS 26.0, *) {
                let provider = try FoundationModelsProvider()
                agent.setProvider(provider)
            }
            #endif

            agent.applyTemplate(template)
            let prompt = template.initialPrompt ?? "Run this template"
            let response = try await agent.run(prompt)
            return response
        }
    }
}
#endif
