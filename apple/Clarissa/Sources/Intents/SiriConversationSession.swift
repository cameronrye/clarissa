import Foundation

/// Maintains conversation history across Siri invocations for follow-up questions
/// Sessions auto-expire after 5 minutes of inactivity
/// Thread-safe via actor isolation
actor SiriConversationSession {
    static let shared = SiriConversationSession()

    private var messages: [(role: String, content: String)] = []
    private var lastActivity: Date = .distantPast

    /// Add a question/answer exchange to the session
    func addExchange(question: String, answer: String) {
        // Clear if expired
        if isExpired() {
            messages.removeAll()
        }

        messages.append((role: "user", content: question))
        messages.append((role: "assistant", content: answer))

        // Enforce max message limit
        let maxMessages = ClarissaConstants.siriSessionMaxMessages
        if messages.count > maxMessages {
            messages = Array(messages.suffix(maxMessages))
        }

        lastActivity = Date()
    }

    /// Build a formatted prompt from conversation history for context
    /// Returns nil if no prior history exists
    func buildHistoryPrompt() -> String? {
        if isExpired() {
            messages.removeAll()
        }

        guard !messages.isEmpty else { return nil }

        var prompt = "Previous conversation:\n"
        for message in messages {
            let label = message.role == "user" ? "User" : "Clarissa"
            prompt += "\(label): \(message.content)\n"
        }
        return prompt
    }

    /// Check if the session has expired (no activity within threshold)
    func isExpired() -> Bool {
        Date().timeIntervalSince(lastActivity) > ClarissaConstants.siriSessionExpirySeconds
    }

    /// Clear the conversation session
    func clear() {
        messages.removeAll()
        lastActivity = .distantPast
    }

    /// Number of messages in the current session
    func messageCount() -> Int {
        if isExpired() { return 0 }
        return messages.count
    }
}
