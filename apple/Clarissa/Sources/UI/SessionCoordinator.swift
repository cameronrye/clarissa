import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif
#if canImport(WebKit)
import WebKit
#endif

/// Coordinates session lifecycle: loading, saving, switching, deletion, and export
@MainActor
final class SessionCoordinator {
    private let agent: Agent

    init(agent: Agent) {
        self.agent = agent
    }

    // MARK: - Session Loading

    /// Load the current session from persistence
    /// - Returns: Chat messages for UI display
    func loadCurrentSession() async -> [ChatMessage] {
        let session = await SessionManager.shared.getCurrentSession()
        let savedMessages = session.messages

        ClarissaLogger.ui.info(
            "Loading current session '\(session.title, privacy: .public)' with \(savedMessages.count) messages"
        )

        let chatMessages = convertSessionMessages(savedMessages)
        ClarissaLogger.ui.info("Loaded \(chatMessages.count) UI messages on startup")

        // Load into agent
        agent.loadMessages(savedMessages)

        // Refresh widgets with current session data
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif

        return chatMessages
    }

    // MARK: - Session Saving

    /// Save the current session to persistence
    func saveCurrentSession() async {
        let messagesToSave = agent.getMessagesForSave()
        await SessionManager.shared.updateCurrentSession(messages: messagesToSave)

        if let sessionId = await SessionManager.shared.getCurrentSessionId() {
            // Tag session with topics for search/filtering
            await SessionManager.shared.tagSession(id: sessionId)

            // Auto-generate summary if the session doesn't have one yet
            #if canImport(FoundationModels)
            if #available(iOS 26.0, macOS 26.0, *) {
                let session = await SessionManager.shared.getCurrentSession()
                if session.summary == nil {
                    if let summary = await SessionSummarizer.shared.summarize(messages: messagesToSave) {
                        await SessionManager.shared.setSummary(summary, for: sessionId)
                    }
                }
            }
            #endif
        }
    }

    // MARK: - Session CRUD

    /// Start a new session, resetting agent state
    func startNewSession() async {
        await agent.resetForNewConversation()
        _ = await SessionManager.shared.startNewSession()
    }

    /// Switch to a different session
    /// - Returns: Chat messages for UI display, or nil if session not found
    func switchToSession(id: UUID) async -> [ChatMessage]? {
        guard let session = await SessionManager.shared.switchToSession(id: id) else {
            ClarissaLogger.ui.error("Failed to switch to session: \(id.uuidString, privacy: .public)")
            return nil
        }

        ClarissaLogger.ui.info(
            "Switching to session: \(session.title, privacy: .public) with \(session.messages.count) messages"
        )

        // Reset provider session to clear cached context from previous conversation
        await agent.resetForNewConversation()

        let chatMessages = convertSessionMessages(session.messages)
        ClarissaLogger.ui.info("Loaded \(chatMessages.count) UI messages from session")

        // Load into agent for context
        agent.loadMessages(session.messages)

        // Refresh widgets after session switch
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif

        return chatMessages
    }

    /// Delete a session
    /// - Returns: Whether the active conversation was deleted (caller should clear UI)
    func deleteSession(id: UUID) async -> Bool {
        let currentId = await SessionManager.shared.getCurrentSessionId()
        let isDeletingActive = currentId == id

        await SessionManager.shared.deleteSession(id: id)

        if isDeletingActive {
            await agent.resetForNewConversation()
            // SessionManager.deleteSession already falls back to sessions.first.
            // Only create a brand new session if no sessions remain.
            if await SessionManager.shared.getCurrentSessionId() == nil {
                _ = await SessionManager.shared.startNewSession()
            }
        }

        return isDeletingActive
    }

    /// Rename a session
    func renameSession(id: UUID, newTitle: String) async {
        await SessionManager.shared.renameSession(id: id, newTitle: newTitle)
    }

    /// Get all sessions for history display
    func getAllSessions() async -> [Session] {
        await SessionManager.shared.getAllSessions()
    }

    /// Get the current session ID
    func getCurrentSessionId() async -> UUID? {
        await SessionManager.shared.getCurrentSessionId()
    }

    // MARK: - Export

    /// Export conversation as markdown text
    func exportConversation(from messages: [ChatMessage]) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        var markdown = "# Clarissa Conversation\n\n"
        markdown += "_Exported on \(dateFormatter.string(from: Date()))_\n\n"
        markdown += "---\n\n"

        for message in messages {
            if message.role != .system {
                markdown += "\(message.toMarkdown())\n\n"
            }
        }

        return markdown
    }

    /// Export conversation as PDF data
    #if canImport(WebKit)
    func exportConversationAsPDF(from messages: [ChatMessage]) async -> Data? {
        let html = exportConversationAsHTML(from: messages)

        // Use DispatchWorkItem timeout to prevent indefinite hangs
        // (e.g., if loadHTMLString fails without triggering a delegate callback)
        return await withCheckedContinuation { continuation in
            var hasResumed = false

            let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 612, height: 792))
            webView.loadHTMLString(html, baseURL: nil)

            // 10-second timeout
            let timeoutWork = DispatchWorkItem { [weak webView] in
                guard !hasResumed else { return }
                hasResumed = true
                if let webView {
                    objc_setAssociatedObject(webView, "delegate", nil, .OBJC_ASSOCIATION_RETAIN)
                }
                ClarissaLogger.ui.warning("PDF export timed out after 10 seconds")
                continuation.resume(returning: nil)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: timeoutWork)

            let delegate = PDFWebViewDelegate { [weak webView] in
                timeoutWork.cancel()
                guard !hasResumed else { return }
                guard let webView else {
                    hasResumed = true
                    continuation.resume(returning: nil)
                    return
                }
                let config = WKPDFConfiguration()
                config.rect = CGRect(x: 0, y: 0, width: 612, height: 792)
                webView.createPDF(configuration: config) { result in
                    guard !hasResumed else { return }
                    hasResumed = true
                    objc_setAssociatedObject(webView, "delegate", nil, .OBJC_ASSOCIATION_RETAIN)
                    switch result {
                    case .success(let data):
                        continuation.resume(returning: data)
                    case .failure:
                        continuation.resume(returning: nil)
                    }
                }
            }
            webView.navigationDelegate = delegate
            objc_setAssociatedObject(webView, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    #endif

    /// Generate styled HTML for PDF export
    func exportConversationAsHTML(from messages: [ChatMessage]) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        var body = ""
        for message in messages where message.role != .system {
            let roleClass: String
            let roleLabel: String
            switch message.role {
            case .user:
                roleClass = "user"
                roleLabel = "You"
            case .assistant:
                roleClass = "assistant"
                roleLabel = "Clarissa"
            case .tool:
                roleClass = "tool"
                roleLabel = message.toolName.map { ToolDisplayNames.format($0) } ?? "Tool"
            case .system:
                continue
            }

            let escapedContent = message.content
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\n", with: "<br>")

            body += """
            <div class="message \(roleClass)">
                <div class="role">\(roleLabel)</div>
                <div class="content">\(escapedContent)</div>
            </div>
            """
        }

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
            body { font-family: -apple-system, sans-serif; padding: 40px; color: #1a1a1a; }
            h1 { color: #7C3AED; font-size: 24px; }
            .meta { color: #888; font-size: 12px; margin-bottom: 20px; }
            .message { margin-bottom: 16px; padding: 12px 16px; border-radius: 12px; }
            .user { background: linear-gradient(135deg, #7C3AED, #9333EA); color: white; margin-left: 60px; }
            .assistant { background: #F3F4F6; margin-right: 60px; }
            .tool { background: #EEF2FF; margin-right: 60px; font-size: 13px; }
            .role { font-weight: 600; font-size: 11px; text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 4px; opacity: 0.7; }
            .content { font-size: 14px; line-height: 1.5; }
        </style>
        </head>
        <body>
            <h1>Clarissa Conversation</h1>
            <div class="meta">Exported on \(dateFormatter.string(from: Date()))</div>
            <hr>
            \(body)
        </body>
        </html>
        """
    }

    // MARK: - Share Extension

    /// Check for shared content from the Share Extension
    /// - Returns: The latest shared result, if any
    func checkForSharedResults() -> SharedResult? {
        let results = SharedResultStore.load()
        guard let latest = results.last else { return nil }
        SharedResultStore.clear()
        return latest
    }

    /// Build a chat message from a shared result
    func buildSharedResultMessage(_ result: SharedResult) -> ChatMessage {
        let content: String
        switch result.type {
        case .text:
            content = "I shared some text with you. Here's the analysis:\n\n\(result.analysis)"
        case .url:
            content = "I shared a link (\(result.originalContent)) with you. Here's what I found:\n\n\(result.analysis)"
        case .image:
            content = "I shared an image with you. \(result.analysis)"
        }
        return ChatMessage(role: .assistant, content: content)
    }

    // MARK: - Private Helpers

    // MARK: - Pin / Favorite / Tag Bridges

    /// Toggle pin on a message in persistence, returns updated pin state
    func toggleMessagePin(messageId: UUID) async {
        await SessionManager.shared.toggleMessagePin(messageId: messageId)
    }

    /// Toggle favorite on a session
    func toggleFavorite(sessionId: UUID) async {
        await SessionManager.shared.toggleFavorite(id: sessionId)
    }

    /// Add a manual tag to a session
    func addTag(_ tag: String, to sessionId: UUID) async {
        await SessionManager.shared.addTag(tag, to: sessionId)
    }

    /// Remove a manual tag from a session
    func removeTag(_ tag: String, from sessionId: UUID) async {
        await SessionManager.shared.removeTag(tag, from: sessionId)
    }

    /// Set summary for a session
    func setSummary(_ summary: String, for sessionId: UUID) async {
        await SessionManager.shared.setSummary(summary, for: sessionId)
    }

    // MARK: - Private Helpers

    /// Convert persisted Message objects to ChatMessage objects for UI display
    private func convertSessionMessages(_ messages: [Message]) -> [ChatMessage] {
        var chatMessages: [ChatMessage] = []
        for message in messages {
            switch message.role {
            case .user, .assistant:
                var chatMessage = ChatMessage(role: message.role, content: message.content)
                chatMessage.imageData = message.imageData
                chatMessage.isPinned = message.isPinned ?? false
                chatMessages.append(chatMessage)
            case .tool:
                var chatMessage = ChatMessage(
                    role: .tool,
                    content: ToolDisplayNames.format(message.toolName ?? "tool"),
                    toolName: message.toolName,
                    toolStatus: .completed
                )
                chatMessage.toolResult = message.content
                chatMessages.append(chatMessage)
            case .system:
                break  // Skip system messages in UI
            }
        }
        return chatMessages
    }
}

// MARK: - PDF Export Helper

#if canImport(WebKit)
/// Navigation delegate that fires a callback when a WKWebView finishes loading
private class PDFWebViewDelegate: NSObject, WKNavigationDelegate {
    let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Small delay to ensure rendering is complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [onFinish] in
            onFinish()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        // Resume continuation on failure to avoid indefinite hang
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [onFinish] in
            onFinish()
        }
    }
}
#endif
