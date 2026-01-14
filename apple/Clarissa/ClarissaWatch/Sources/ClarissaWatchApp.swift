import Combine
import SwiftUI
import WatchConnectivity
import WatchKit

@main
struct ClarissaWatchApp: App {
    /// Extension delegate for handling background tasks
    @WKApplicationDelegateAdaptor(ExtensionDelegate.self) var extensionDelegate

    @StateObject private var appState = WatchAppState()

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(appState)
                .task {
                    // Check for screenshot mode
                    if WatchDemoData.isScreenshotMode {
                        appState.setupDemoMode()
                    } else {
                        // Activate WatchConnectivity
                        WatchConnectivityClient.shared.activate()

                        // Schedule background refresh to keep connectivity alive
                        BackgroundTaskManager.shared.scheduleBackgroundRefresh()
                    }
                }
        }
    }
}

// MARK: - Response History Item

/// A single query/response pair for history
struct ResponseHistoryItem: Identifiable, Codable {
    let id: UUID
    let query: String
    let response: String
    let timestamp: Date

    init(query: String, response: String) {
        self.id = UUID()
        self.query = query
        self.response = response
        self.timestamp = Date()
    }
}

// MARK: - Quick Actions

/// Pre-defined quick actions for common queries
enum QuickAction: String, CaseIterable, Identifiable {
    case weather = "Weather"
    case nextMeeting = "Next meeting"
    case setTimer = "Set a 5 minute timer"
    case reminders = "What are my reminders?"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .weather: return "cloud.sun.fill"
        case .nextMeeting: return "calendar"
        case .setTimer: return "timer"
        case .reminders: return "checklist"
        }
    }

    var query: String {
        switch self {
        case .weather: return "What's the weather like?"
        case .nextMeeting: return "When is my next meeting?"
        case .setTimer: return "Set a timer for 5 minutes"
        case .reminders: return "What are my reminders for today?"
        }
    }

    var shortLabel: String {
        switch self {
        case .weather: return "Weather"
        case .nextMeeting: return "Next Meeting"
        case .setTimer: return "5min Timer"
        case .reminders: return "Reminders"
        }
    }
}

// MARK: - App State

/// App state for the Watch app
@MainActor
final class WatchAppState: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var isReachable: Bool = false
    @Published var responseHistory: [ResponseHistoryItem] = []
    @Published var pendingRequestId: UUID?
    @Published var pendingQuery: String?
    @Published var status: QueryStatus = .idle

    /// Maximum number of history items to keep
    private let maxHistoryItems = 5

    /// UserDefaults key for persisting history
    private let historyKey = "responseHistory"

    enum QueryStatus: Equatable {
        case idle
        case listening
        case sending
        case waiting
        case processing(String)
        case error(String)
    }

    private let connectivity = WatchConnectivityClient.shared
    private var cancellables = Set<AnyCancellable>()

    /// The most recent response (for backward compatibility)
    var lastResponse: String? {
        responseHistory.first?.response
    }

    init() {
        loadHistory()
        setupConnectivityObserver()
        setupCallbacks()
    }

    // MARK: - History Management

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let history = try? JSONDecoder().decode([ResponseHistoryItem].self, from: data) else {
            return
        }
        responseHistory = history
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(responseHistory) else { return }
        UserDefaults.standard.set(data, forKey: historyKey)
    }

    private func addToHistory(query: String, response: String) {
        let item = ResponseHistoryItem(query: query, response: response)
        responseHistory.insert(item, at: 0)

        // Trim to max items
        if responseHistory.count > maxHistoryItems {
            responseHistory = Array(responseHistory.prefix(maxHistoryItems))
        }

        saveHistory()
    }

    /// Clear all history
    func clearHistory() {
        responseHistory.removeAll()
        saveHistory()
    }

    // MARK: - Connectivity

    private func setupConnectivityObserver() {
        connectivity.$isReachable
            .receive(on: DispatchQueue.main)
            .sink { [weak self] reachable in
                self?.isReachable = reachable
            }
            .store(in: &cancellables)
    }

    private func setupCallbacks() {
        connectivity.onResponse = { [weak self] response in
            Task { @MainActor in
                // Add to history with the pending query
                if let query = self?.pendingQuery {
                    self?.addToHistory(query: query, response: response.text)
                }
                self?.status = .idle
                self?.pendingRequestId = nil
                self?.pendingQuery = nil
                HapticManager.responseReceived()
            }
        }

        connectivity.onStatus = { [weak self] status in
            Task { @MainActor in
                switch status.status {
                case .received:
                    self?.status = .waiting
                case .thinking:
                    self?.status = .processing("Thinking")
                    HapticManager.statusChange()
                case .usingTool:
                    self?.status = .processing("Using tools")
                    HapticManager.statusChange()
                case .processing:
                    self?.status = .processing("Processing")
                case .completed:
                    self?.status = .idle
                }
            }
        }

        connectivity.onError = { [weak self] error in
            Task { @MainActor in
                self?.status = .error(error.message)
                self?.pendingRequestId = nil
                self?.pendingQuery = nil
                HapticManager.error()
            }
        }
    }

    /// Send a query to the iPhone
    func sendQuery(_ text: String) {
        guard !text.isEmpty else { return }

        pendingQuery = text
        status = .sending
        HapticManager.querySent()

        if let requestId = connectivity.sendQuery(text) {
            pendingRequestId = requestId
            status = .waiting
        } else {
            status = .error(connectivity.lastError ?? "Failed to send")
            pendingQuery = nil
            HapticManager.error()
        }
    }

    /// Send a quick action query
    func sendQuickAction(_ action: QuickAction) {
        sendQuery(action.query)
    }

    /// Clear any error state
    func clearError() {
        if case .error = status {
            status = .idle
        }
    }

    // MARK: - Demo Mode

    /// Setup demo mode for App Store screenshots
    func setupDemoMode() {
        isReachable = true
        let scenario = WatchDemoData.currentScenario

        switch scenario {
        case .welcome:
            // Empty state - no history
            responseHistory = []
            status = .idle
        case .response:
            // Show a weather response
            responseHistory = [WatchDemoData.demoResponse]
            status = .idle
        case .quickActions:
            // Show meeting response (distinct from weather in response screenshot)
            responseHistory = [WatchDemoData.demoHistoryItems[1]]  // "Next meeting?" response
            status = .idle
        case .voiceInput:
            // Listening state
            responseHistory = []
            status = .listening
        case .processing:
            // Processing state
            responseHistory = []
            pendingQuery = "What's the weather?"
            status = .processing("Thinking")
        case .history:
            // History list with multiple items
            responseHistory = WatchDemoData.demoHistoryItems
            status = .idle
        case .historyDetail:
            // History detail - will show first item
            responseHistory = WatchDemoData.demoHistoryItems
            status = .idle
        case .error:
            // Error state
            responseHistory = Array(WatchDemoData.demoHistoryItems.prefix(1))
            status = .error(WatchDemoData.demoErrorMessage)
        case .connected:
            // Connected state with calendar response (distinct from weather in response screenshot)
            responseHistory = [WatchDemoData.demoConnectedResponse]
            status = .idle
        case .sending:
            // Sending state
            responseHistory = []
            pendingQuery = WatchDemoData.demoSendingQuery
            status = .sending
        }
    }
}

