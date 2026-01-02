import SwiftUI
import WatchConnectivity
import WatchKit

@main
struct ClarissaWatchApp: App {
    @StateObject private var appState = WatchAppState()
    
    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(appState)
                .task {
                    // Activate WatchConnectivity
                    WatchConnectivityClient.shared.activate()
                }
        }
    }
}

/// App state for the Watch app
@MainActor
final class WatchAppState: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var lastResponse: String?
    @Published var pendingRequestId: UUID?
    @Published var status: QueryStatus = .idle
    
    enum QueryStatus: Equatable {
        case idle
        case listening
        case sending
        case waiting
        case processing(String)
        case error(String)
    }
    
    private let connectivity = WatchConnectivityClient.shared
    
    init() {
        setupCallbacks()
    }
    
    private func setupCallbacks() {
        connectivity.onResponse = { [weak self] response in
            Task { @MainActor in
                self?.lastResponse = response.text
                self?.status = .idle
                self?.pendingRequestId = nil
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
                HapticManager.error()
            }
        }
    }
    
    /// Send a query to the iPhone
    func sendQuery(_ text: String) {
        guard !text.isEmpty else { return }

        status = .sending
        HapticManager.querySent()

        if let requestId = connectivity.sendQuery(text) {
            pendingRequestId = requestId
            status = .waiting
        } else {
            status = .error(connectivity.lastError ?? "Failed to send")
            HapticManager.error()
        }
    }
    
    /// Check if iPhone is reachable
    var isReachable: Bool {
        connectivity.isReachable
    }
    
    /// Clear any error state
    func clearError() {
        if case .error = status {
            status = .idle
        }
    }
}

