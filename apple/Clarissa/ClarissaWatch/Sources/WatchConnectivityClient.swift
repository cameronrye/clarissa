import Foundation
import WatchConnectivity

/// WatchConnectivity client for the Apple Watch app
/// Sends queries to iPhone and receives responses
@MainActor
final class WatchConnectivityClient: NSObject, ObservableObject {
    static let shared = WatchConnectivityClient()
    
    @Published private(set) var isReachable: Bool = false
    @Published private(set) var isCompanionAppInstalled: Bool = false
    @Published private(set) var lastError: String?
    
    /// Called when a response is received from iPhone
    var onResponse: ((QueryResponse) -> Void)?
    
    /// Called when a status update is received
    var onStatus: ((ProcessingStatus) -> Void)?
    
    /// Called when an error is received
    var onError: ((ErrorInfo) -> Void)?
    
    private var session: WCSession?
    private var pendingRequest: QueryRequest?
    
    private override init() {
        super.init()
    }
    
    /// Activate the WatchConnectivity session
    func activate() {
        guard WCSession.isSupported() else { return }
        
        session = WCSession.default
        session?.delegate = self
        session?.activate()
    }
    
    /// Send a query to the iPhone for processing
    /// - Parameter text: The user's query text
    /// - Returns: The request ID for tracking
    @discardableResult
    func sendQuery(_ text: String) -> UUID? {
        guard let session = session else {
            lastError = "Watch connectivity not initialized"
            return nil
        }
        
        guard session.isReachable else {
            lastError = "iPhone not reachable"
            return nil
        }
        
        let request = QueryRequest(text: text)
        pendingRequest = request
        
        do {
            let message = WatchMessage.query(request)
            let dict = try message.toDictionary()
            
            session.sendMessage(dict, replyHandler: nil) { [weak self] error in
                Task { @MainActor in
                    self?.lastError = error.localizedDescription
                    self?.onError?(ErrorInfo(
                        requestId: request.id,
                        message: error.localizedDescription,
                        isRecoverable: true
                    ))
                }
            }
            
            lastError = nil
            return request.id
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }
    
    /// Check if iPhone is reachable
    func checkReachability() -> Bool {
        return session?.isReachable ?? false
    }
    
    /// Ping the iPhone to check connectivity
    func ping() async -> Bool {
        guard let session = session, session.isReachable else { return false }
        
        return await withCheckedContinuation { continuation in
            do {
                let message = try WatchMessage.ping.toDictionary()
                session.sendMessage(message, replyHandler: { response in
                    // Received pong
                    continuation.resume(returning: true)
                }, errorHandler: { _ in
                    continuation.resume(returning: false)
                })
            } catch {
                continuation.resume(returning: false)
            }
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityClient: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            if activationState == .activated {
                isReachable = session.isReachable
                #if os(watchOS)
                isCompanionAppInstalled = session.isCompanionAppInstalled
                #endif
            }
        }
    }
    
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            isReachable = session.isReachable
        }
    }
    
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            await handleReceivedMessage(message)
        }
    }
    
    @MainActor
    private func handleReceivedMessage(_ message: [String: Any]) async {
        do {
            let watchMessage = try WatchMessage.from(dictionary: message)
            
            switch watchMessage {
            case .response(let response):
                pendingRequest = nil
                onResponse?(response)
                
            case .status(let status):
                onStatus?(status)
                
            case .error(let error):
                pendingRequest = nil
                lastError = error.message
                onError?(error)
                
            case .query, .ping, .pong:
                // These are sent from Watch, not received
                break
            }
        } catch {
            lastError = "Failed to decode message"
        }
    }
}

