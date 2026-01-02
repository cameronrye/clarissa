import Foundation
import WatchConnectivity

/// Manages WatchConnectivity between iPhone and Apple Watch
/// This class runs on the iPhone and handles incoming requests from Watch
@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()
    
    @Published private(set) var isReachable: Bool = false
    @Published private(set) var isPaired: Bool = false
    @Published private(set) var isWatchAppInstalled: Bool = false
    
    /// Callback when a query is received from Watch
    var onQueryReceived: ((QueryRequest) async -> QueryResponse)?
    
    /// Callback for status updates to send to Watch
    var onStatusUpdate: ((ProcessingStatus) -> Void)?
    
    private var session: WCSession?
    
    private override init() {
        super.init()
    }
    
    /// Start the WatchConnectivity session
    func activate() {
        guard WCSession.isSupported() else {
            ClarissaLogger.agent.info("WatchConnectivity not supported on this device")
            return
        }
        
        session = WCSession.default
        session?.delegate = self
        session?.activate()
        ClarissaLogger.agent.info("WatchConnectivity session activating...")
    }
    
    /// Send a response back to the Watch
    func sendResponse(_ response: QueryResponse) {
        guard let session = session, session.isReachable else {
            ClarissaLogger.agent.warning("Cannot send response - Watch not reachable")
            return
        }
        
        do {
            let message = WatchMessage.response(response)
            let dict = try message.toDictionary()
            session.sendMessage(dict, replyHandler: nil) { error in
                ClarissaLogger.agent.error("Failed to send response to Watch: \(error.localizedDescription)")
            }
        } catch {
            ClarissaLogger.agent.error("Failed to encode response: \(error.localizedDescription)")
        }
    }
    
    /// Send a status update to the Watch
    func sendStatus(_ status: ProcessingStatus) {
        guard let session = session, session.isReachable else { return }
        
        do {
            let message = WatchMessage.status(status)
            let dict = try message.toDictionary()
            session.sendMessage(dict, replyHandler: nil, errorHandler: nil)
        } catch {
            ClarissaLogger.agent.error("Failed to encode status: \(error.localizedDescription)")
        }
    }
    
    /// Send an error to the Watch
    func sendError(_ error: ErrorInfo) {
        guard let session = session, session.isReachable else { return }
        
        do {
            let message = WatchMessage.error(error)
            let dict = try message.toDictionary()
            session.sendMessage(dict, replyHandler: nil, errorHandler: nil)
        } catch {
            ClarissaLogger.agent.error("Failed to encode error: \(error.localizedDescription)")
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            if let error = error {
                ClarissaLogger.agent.error("WatchConnectivity activation failed: \(error.localizedDescription)")
                return
            }
            
            switch activationState {
            case .activated:
                ClarissaLogger.agent.info("WatchConnectivity activated")
                updateSessionState(session)
            case .inactive:
                ClarissaLogger.agent.info("WatchConnectivity inactive")
            case .notActivated:
                ClarissaLogger.agent.info("WatchConnectivity not activated")
            @unknown default:
                break
            }
        }
    }
    
    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        ClarissaLogger.agent.info("WatchConnectivity session became inactive")
    }
    
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        ClarissaLogger.agent.info("WatchConnectivity session deactivated")
        // Reactivate for switching watches
        session.activate()
    }
    #endif
    
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            isReachable = session.isReachable
            ClarissaLogger.agent.info("Watch reachability changed: \(session.isReachable)")
        }
    }
    
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleReceivedMessage(message)
    }
    
    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        handleReceivedMessage(message, replyHandler: replyHandler)
    }
    
    private nonisolated func handleReceivedMessage(
        _ message: [String: Any],
        replyHandler: (([String: Any]) -> Void)? = nil
    ) {
        Task { @MainActor in
            do {
                let watchMessage = try WatchMessage.from(dictionary: message)
                await processMessage(watchMessage, replyHandler: replyHandler)
            } catch {
                ClarissaLogger.agent.error("Failed to decode Watch message: \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    private func processMessage(
        _ message: WatchMessage,
        replyHandler: (([String: Any]) -> Void)?
    ) async {
        switch message {
        case .query(let request):
            ClarissaLogger.agent.info("Received query from Watch: \(request.text.prefix(50))...")

            // Send immediate acknowledgment
            sendStatus(ProcessingStatus(requestId: request.id, status: .received))

            // Process the query
            if let handler = onQueryReceived {
                let response = await handler(request)
                sendResponse(response)
            } else {
                sendError(ErrorInfo(
                    requestId: request.id,
                    message: "iPhone app not ready",
                    isRecoverable: true
                ))
            }

        case .ping:
            // Respond with pong
            if let replyHandler = replyHandler {
                do {
                    let pong = try WatchMessage.pong.toDictionary()
                    replyHandler(pong)
                } catch {
                    ClarissaLogger.agent.error("Failed to send pong: \(error.localizedDescription)")
                }
            }

        case .response, .status, .error, .pong:
            // These are sent from iPhone, not received
            break
        }
    }

    @MainActor
    private func updateSessionState(_ session: WCSession) {
        isReachable = session.isReachable
        #if os(iOS)
        isPaired = session.isPaired
        isWatchAppInstalled = session.isWatchAppInstalled
        #endif
    }
}

