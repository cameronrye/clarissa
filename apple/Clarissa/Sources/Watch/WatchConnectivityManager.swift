#if os(iOS)
import ClarissaKit
import Foundation
@preconcurrency import WatchConnectivity

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
        // Extract values before crossing actor boundary
        let isReachable = session.isReachable
        let isPaired = session.isPaired
        let isWatchAppInstalled = session.isWatchAppInstalled
        let errorDescription = error?.localizedDescription

        Task { @MainActor in
            if let errorDescription = errorDescription {
                ClarissaLogger.agent.error("WatchConnectivity activation failed: \(errorDescription)")
                return
            }

            switch activationState {
            case .activated:
                ClarissaLogger.agent.info("WatchConnectivity activated")
                self.isReachable = isReachable
                self.isPaired = isPaired
                self.isWatchAppInstalled = isWatchAppInstalled
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
        // Extract value before crossing actor boundary
        let reachable = session.isReachable
        Task { @MainActor in
            isReachable = reachable
            ClarissaLogger.agent.info("Watch reachability changed: \(reachable)")
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
        // Decode message in nonisolated context first
        do {
            let watchMessage = try WatchMessage.from(dictionary: message)

            // Build reply dictionary in nonisolated context before crossing actor boundary
            // This avoids bridging the non-Sendable replyHandler closure across isolation domains
            if let replyHandler = replyHandler {
                if case .ping = watchMessage {
                    let replyDict = (try? WatchMessage.pong.toDictionary()) ?? [:]
                    replyHandler(replyDict)
                } else {
                    replyHandler([:])
                }
            }

            Task { @MainActor in
                await processMessage(watchMessage, replyHandler: nil)
            }
        } catch {
            ClarissaLogger.agent.error("Failed to decode Watch message: \(error.localizedDescription)")
            replyHandler?([:])
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
}
#endif
