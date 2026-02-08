import Foundation

/// Detects user intent from message text using regex patterns and prefetches
/// relevant tool data so the agent can respond with richer context.
///
/// Only activates when Foundation Models is the active provider (free, on-device)
/// and the user has opted in via the "Proactive Context" setting.
@MainActor
enum ProactiveContext {

    // MARK: - Settings

    /// UserDefaults key for the opt-in toggle (defaults to OFF)
    static let settingsKey = "proactiveContextEnabled"

    /// Whether the user has opted in
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: settingsKey)
    }

    // MARK: - Intent Detection

    /// Detected intent with the tool name and arguments to prefetch
    struct DetectedIntent: Sendable {
        let toolName: String
        let arguments: String
        /// Short label for the detected intent (e.g., "weather", "calendar")
        let label: String
    }

    /// Scan a user message for explicit intent signals using regex patterns.
    /// Returns all detected intents (may be empty).
    static func detectIntents(in message: String) -> [DetectedIntent] {
        let lower = message.lowercased()
        var intents: [DetectedIntent] = []

        // Weather patterns
        if matchesWeather(lower) {
            let location = extractWeatherLocation(from: message)
            let args = location.map { "{\"location\":\"\($0)\"}" } ?? "{}"
            intents.append(DetectedIntent(toolName: "weather", arguments: args, label: "weather"))
        }

        // Calendar / time patterns
        if matchesCalendar(lower) {
            intents.append(DetectedIntent(toolName: "calendar", arguments: "{\"action\":\"list\"}", label: "calendar"))
        }

        return intents
    }

    // MARK: - Weather Detection

    /// Strong keywords that unambiguously indicate weather intent
    private static let strongWeatherKeywords: Set<String> = [
        "weather", "forecast", "temperature"
    ]

    /// Contextual weather patterns — require weather-related phrasing to avoid
    /// false positives like "hot take", "cold case", "warm welcome", "coat of arms"
    private static let contextualWeatherPatterns: [String] = [
        #"\b(is it|will it|going to)\s+(rain|snow|be (cold|hot|warm|sunny|cloudy|windy))"#,
        #"\b(rain|snow)\s+(today|tomorrow|tonight|this week|later)"#,
        #"\bdo i need\s+(an?\s+)?(umbrella|jacket|coat)\b"#,
        #"\b(how('s| is) the weather|what('s| is) the (weather|temperature|forecast))\b"#,
    ]

    private static func matchesWeather(_ text: String) -> Bool {
        // Strong keywords always match
        let words = Set(text.components(separatedBy: .alphanumerics.inverted).filter { !$0.isEmpty })
        if !words.isDisjoint(with: strongWeatherKeywords) { return true }

        // Contextual patterns require weather-specific phrasing
        for pattern in contextualWeatherPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
                return true
            }
        }
        return false
    }

    /// Try to extract a location from the message (e.g., "weather in Paris")
    private static func extractWeatherLocation(from message: String) -> String? {
        // Pattern: "weather in <location>" or "forecast for <location>"
        let patterns = [
            #"(?:weather|forecast|temperature)\s+(?:in|for|at)\s+(.+?)(?:\?|$|\.)"#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: message) {
                let location = String(message[range]).trimmingCharacters(in: .whitespaces)
                if !location.isEmpty { return location }
            }
        }
        return nil
    }

    // MARK: - Calendar Detection

    private static let calendarPatterns: [String] = [
        // Require calendar-adjacent context — bare "today" triggers too often
        // ("What happened today?", "I'm tired today")
        #"\b(what('s| is|'re| are)\s+(on\s+)?(my\s+)?(calendar|schedule|agenda))\b"#,
        #"\b(schedule|meeting|appointment)\b"#,
        #"\b(am i|are we)\s+(busy|free|available)\b"#,
        #"\b(at \d{1,2}(:\d{2})?\s*(am|pm))\b"#,
        #"\b(next (monday|tuesday|wednesday|thursday|friday|saturday|sunday))\b"#,
        #"\b(do i have)\s+.{0,20}\b(today|tomorrow|tonight|this week)\b"#,
    ]

    private static func matchesCalendar(_ text: String) -> Bool {
        for pattern in calendarPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
                return true
            }
        }
        return false
    }

    // MARK: - Prefetch

    /// Prefetch data for detected intents in parallel with a 2-second timeout.
    /// Returns formatted context string (capped at 100 tokens / ~400 chars).
    static func prefetch(intents: [DetectedIntent], toolRegistry: ToolRegistry) async -> String? {
        guard !intents.isEmpty else { return nil }

        // Only prefetch tools that are enabled
        let enabledNames = ToolSettings.shared.enabledToolNames
        let validIntents = intents.filter { enabledNames.contains($0.toolName) }
        guard !validIntents.isEmpty else { return nil }

        ClarissaLogger.agent.info("Proactive: prefetching \(validIntents.map(\.label))")

        // Run all prefetches in parallel with a 2-second timeout
        let results = await withTaskGroup(of: (String, String?).self, returning: [(String, String)].self) { group in
            for intent in validIntents {
                group.addTask {
                    do {
                        let result = try await withThrowingTaskGroup(of: String.self) { inner in
                            inner.addTask {
                                try await toolRegistry.execute(name: intent.toolName, arguments: intent.arguments)
                            }
                            inner.addTask {
                                try await Task.sleep(for: .seconds(2))
                                throw CancellationError()
                            }
                            guard let first = try await inner.next() else { return "" }
                            inner.cancelAll()
                            return first
                        }
                        return (intent.label, result as String?)
                    } catch {
                        ClarissaLogger.agent.info("Proactive: \(intent.label) prefetch failed: \(error.localizedDescription)")
                        return (intent.label, nil)
                    }
                }
            }

            var collected: [(String, String)] = []
            for await (label, result) in group {
                if let result { collected.append((label, result)) }
            }
            return collected
        }

        guard !results.isEmpty else { return nil }

        // Format results, capped at ~400 characters (~100 tokens)
        var context = "PROACTIVE CONTEXT (auto-fetched, may be useful):"
        let maxChars = 400
        var remaining = maxChars

        for (label, result) in results {
            let prefix = "\n[\(label)] "
            // Truncate each result to fit budget
            let available = remaining - prefix.count
            guard available > 20 else { break }
            let truncated = result.count > available ? String(result.prefix(available - 3)) + "..." : result
            context += prefix + truncated
            remaining -= prefix.count + truncated.count
        }

        ClarissaLogger.agent.info("Proactive: injected \(context.count) chars of context")
        return context
    }
}
