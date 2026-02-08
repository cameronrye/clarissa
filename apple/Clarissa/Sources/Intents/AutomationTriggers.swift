import Foundation
import AppIntents
#if canImport(UIKit)
import UIKit
#endif
#if canImport(CoreLocation)
import CoreLocation
#endif

// MARK: - Automation Trigger Manager

/// Registers and manages automation triggers for time-of-day, location,
/// and Focus mode changes. Triggers execute tool chains or templates
/// and deliver results via notifications.
@MainActor
final class AutomationManager: ObservableObject {
    static let shared = AutomationManager()

    @Published var triggers: [AutomationTrigger] = []

    static let settingsKey = "automationTriggersEnabled"

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.settingsKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.settingsKey) }
    }

    private init() {
        Task { triggers = await AutomationTriggerStore.shared.load() }
    }

    func reload() async {
        triggers = await AutomationTriggerStore.shared.load()
    }

    func addTrigger(_ trigger: AutomationTrigger) async throws {
        try await AutomationTriggerStore.shared.add(trigger)
        await reload()
    }

    func deleteTrigger(id: String) async throws {
        try await AutomationTriggerStore.shared.delete(id: id)
        await reload()
    }

    func toggleTrigger(id: String) async throws {
        if var trigger = triggers.first(where: { $0.id == id }) {
            trigger.isEnabled.toggle()
            try await AutomationTriggerStore.shared.update(trigger)
            await reload()
        }
    }
}

// MARK: - Automation Trigger Model

/// A trigger that runs a tool chain or template based on a condition
struct AutomationTrigger: Codable, Identifiable, Sendable {
    let id: String
    var name: String
    var isEnabled: Bool
    var condition: TriggerCondition
    var action: TriggerAction

    enum TriggerCondition: Codable, Sendable {
        /// Fire at a specific time each day
        case timeOfDay(hour: Int, minute: Int, days: Set<ScheduledCheckIn.Weekday>)
        /// Fire when arriving at a saved location
        case location(latitude: Double, longitude: Double, radius: Double, name: String)
        /// Fire when a Focus mode activates
        case focusMode(modeName: String)
    }

    enum TriggerAction: Codable, Sendable {
        case runChain(chainId: String)
        case runTemplate(templateId: String)
    }
}

// MARK: - Trigger Store

actor AutomationTriggerStore {
    static let shared = AutomationTriggerStore()

    private let fileName = "automation_triggers.json"

    private var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return docs.appendingPathComponent(fileName)
    }

    func load() -> [AutomationTrigger] {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let triggers = try? JSONDecoder().decode([AutomationTrigger].self, from: data) else {
            return []
        }
        return triggers
    }

    func save(_ triggers: [AutomationTrigger]) throws {
        let data = try JSONEncoder().encode(triggers)
        try data.write(to: fileURL, options: .atomic)
    }

    func add(_ trigger: AutomationTrigger) throws {
        var triggers = load()
        triggers.append(trigger)
        try save(triggers)
    }

    func delete(id: String) throws {
        var triggers = load()
        triggers.removeAll { $0.id == id }
        try save(triggers)
    }

    func update(_ trigger: AutomationTrigger) throws {
        var triggers = load()
        if let index = triggers.firstIndex(where: { $0.id == trigger.id }) {
            triggers[index] = trigger
        }
        try save(triggers)
    }
}

// MARK: - Time-Based Trigger Observer

/// Checks time-based automation triggers when significant system time changes occur
/// (midnight crossings, timezone changes, device unlock after long sleep).
///
/// Note: Despite the name "FocusModeObserver", iOS does not provide an API to detect
/// Focus mode activation. The `.focusMode` trigger condition is evaluated heuristically
/// at time-change boundaries only — it will NOT fire when a user manually toggles Focus.
#if os(iOS)
@MainActor
final class FocusModeObserver {
    static let shared = FocusModeObserver()

    private init() {}

    /// Start observing significant time changes to evaluate time-based triggers.
    /// Note: This does NOT observe Focus mode activation directly (no iOS API for that).
    func startObserving() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSignificantTimeChange),
            name: UIApplication.significantTimeChangeNotification,
            object: nil
        )
    }

    /// Stop observing and clean up notification observer
    func stopObserving() {
        NotificationCenter.default.removeObserver(
            self,
            name: UIApplication.significantTimeChangeNotification,
            object: nil
        )
    }

    @objc private func handleSignificantTimeChange() {
        Task { @MainActor in
            // Check time-based triggers
            let triggers = await AutomationTriggerStore.shared.load()
            let now = Date()
            let calendar = Calendar.current
            let hour = calendar.component(.hour, from: now)
            let minute = calendar.component(.minute, from: now)
            let weekday = calendar.component(.weekday, from: now)

            for trigger in triggers where trigger.isEnabled {
                if case .timeOfDay(let triggerHour, let triggerMinute, let days) = trigger.condition {
                    guard let day = ScheduledCheckIn.Weekday(calendarWeekday: weekday),
                          days.contains(day),
                          hour == triggerHour,
                          abs(minute - triggerMinute) <= 5 else { continue }

                    await executeTriggerAction(trigger.action)
                }
            }
        }
    }

    /// Execute a trigger action
    private func executeTriggerAction(_ action: AutomationTrigger.TriggerAction) async {
        do {
            let result: String

            switch action {
            case .runChain(let chainId):
                let chains = await ToolChain.allChains()
                guard let chain = chains.first(where: { $0.id == chainId }) else { return }
                let executor = ToolChainExecutor()
                let chainResult = try await executor.execute(chain: chain)
                result = chainResult.synthesisContext

            case .runTemplate(let templateId):
                let templates = await ConversationTemplate.allTemplates()
                guard let template = templates.first(where: { $0.id == templateId }) else { return }
                let agent = Agent()
                #if canImport(FoundationModels)
                if #available(iOS 26.0, macOS 26.0, *) {
                    let provider = try FoundationModelsProvider()
                    agent.setProvider(provider)
                }
                #endif
                agent.applyTemplate(template)
                result = try await agent.run(template.initialPrompt ?? "Run template")
            }

            // Deliver result as notification
            NotificationManager.shared.scheduleCheckInNotification(
                title: "Automation",
                body: result,
                checkInId: "trigger-\(UUID().uuidString)",
                at: Date()
            )
        } catch {
            ClarissaLogger.notifications.error("Automation trigger failed: \(error.localizedDescription)")
        }
    }
}
#endif
