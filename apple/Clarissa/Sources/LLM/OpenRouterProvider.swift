import Foundation

/// Provider using OpenRouter cloud API
public final class OpenRouterProvider: LLMProvider, @unchecked Sendable {
    public let name = "OpenRouter"
    public let maxTools = 50

    private let apiKey: String
    private let model: String
    private let baseURL = URL(string: ClarissaConstants.openRouterBaseURL + ClarissaConstants.openRouterCompletionsPath)!
    private let timeout: TimeInterval = ClarissaConstants.llmApiTimeoutSeconds

    public var isAvailable: Bool {
        get async { !apiKey.isEmpty }
    }

    public init(apiKey: String, model: String = "anthropic/claude-sonnet-4") {
        self.apiKey = apiKey
        self.model = model
    }

    public func streamComplete(
        messages: [Message],
        tools: [ToolDefinition]
    ) -> AsyncThrowingStream<StreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    ClarissaLogger.provider.info("OpenRouter: Starting request to model \(self.model, privacy: .public)")

                    var request = URLRequest(url: baseURL)
                    request.httpMethod = "POST"
                    request.timeoutInterval = timeout
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("Clarissa iOS/1.0", forHTTPHeaderField: "HTTP-Referer")
                    request.setValue("Clarissa", forHTTPHeaderField: "X-Title")

                    let body = buildRequestBody(messages: messages, tools: tools, stream: true)
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw OpenRouterError.invalidResponse
                    }

                    // Handle HTTP errors with detailed messages
                    guard httpResponse.statusCode == 200 else {
                        // Try to read error body with timeout to avoid hanging on malformed streams
                        let errorReadTask = Task<String, Error> {
                            var body = ""
                            for try await line in bytes.lines {
                                body += line
                                // Limit error body size to prevent memory issues
                                if body.count > 4096 { break }
                            }
                            return body
                        }

                        // Wait up to 5 seconds for error body, then cancel
                        let timeoutTask = Task {
                            try await Task.sleep(for: .seconds(5))
                            errorReadTask.cancel()
                        }

                        let errorBody = (try? await errorReadTask.value) ?? ""
                        timeoutTask.cancel()

                        ClarissaLogger.network.error("OpenRouter HTTP error \(httpResponse.statusCode): \(errorBody.prefix(200), privacy: .public)")
                        throw OpenRouterError.httpError(
                            statusCode: httpResponse.statusCode,
                            message: parseErrorMessage(from: errorBody) ?? "Request failed"
                        )
                    }

                    ClarissaLogger.provider.debug("OpenRouter: Streaming response started")
                    var accumulatedContent = ""
                    // Track tool calls by index to properly accumulate streamed arguments
                    var toolCallsById: [Int: (id: String, name: String, arguments: String)] = [:]

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonString = String(line.dropFirst(6))

                        if jsonString == "[DONE]" {
                            // Convert accumulated tool calls to array
                            let toolCalls = toolCallsById.keys.sorted().compactMap { index -> ToolCall? in
                                guard let tc = toolCallsById[index] else { return nil }
                                return ToolCall(id: tc.id, name: tc.name, arguments: tc.arguments)
                            }
                            continuation.yield(StreamChunk(content: nil, toolCalls: toolCalls.isEmpty ? nil : toolCalls, isComplete: true))
                            break
                        }

                        guard let data = jsonString.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                            ClarissaLogger.provider.debug("OpenRouter: Skipping malformed JSON chunk")
                            continue
                        }

                        // Check for mid-stream errors
                        if let error = json["error"] as? [String: Any],
                           let errorMessage = error["message"] as? String {
                            ClarissaLogger.provider.error("OpenRouter stream error: \(errorMessage)")
                            continuation.finish(throwing: OpenRouterError.httpError(statusCode: 500, message: errorMessage))
                            return
                        }

                        guard let choices = json["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any] else {
                            continue
                        }

                        if let content = delta["content"] as? String, content != "null" {
                            // Filter out literal "null" string which can occur with some model quirks
                            accumulatedContent += content
                            continuation.yield(StreamChunk(content: content, toolCalls: nil, isComplete: false))
                        }

                        // Handle streaming tool calls - arguments come in chunks
                        if let toolCallsData = delta["tool_calls"] as? [[String: Any]] {
                            for tcData in toolCallsData {
                                guard let index = tcData["index"] as? Int else { continue }

                                // Get or create tool call entry
                                var existing = toolCallsById[index] ?? (id: "", name: "", arguments: "")

                                // Update ID if present (usually only in first chunk)
                                if let id = tcData["id"] as? String, !id.isEmpty {
                                    existing.id = id
                                }

                                if let function = tcData["function"] as? [String: Any] {
                                    // Update name if present (usually only in first chunk)
                                    if let name = function["name"] as? String, !name.isEmpty {
                                        existing.name = name
                                    }
                                    // Accumulate arguments (streamed in chunks)
                                    if let args = function["arguments"] as? String {
                                        existing.arguments += args
                                    }
                                }

                                toolCallsById[index] = existing
                            }
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Parse error message from API response
    private func parseErrorMessage(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // Try common error response formats
        if let error = json["error"] as? [String: Any] {
            return error["message"] as? String
        }
        if let message = json["message"] as? String {
            return message
        }
        if let error = json["error"] as? String {
            return error
        }
        return nil
    }
    
    private func buildRequestBody(messages: [Message], tools: [ToolDefinition], stream: Bool) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "stream": stream,
            "messages": messages.map { messageToDict($0) }
        ]
        
        if !tools.isEmpty {
            body["tools"] = tools.map { toolToDict($0) }
        }
        
        return body
    }
    
    private func messageToDict(_ message: Message) -> [String: Any] {
        var dict: [String: Any] = [
            "role": message.role.rawValue,
            "content": message.content
        ]
        
        if let toolCalls = message.toolCalls {
            dict["tool_calls"] = toolCalls.map {
                ["id": $0.id, "type": "function", "function": ["name": $0.name, "arguments": $0.arguments]]
            }
        }
        
        if let toolCallId = message.toolCallId {
            dict["tool_call_id"] = toolCallId
        }
        
        return dict
    }
    
    private func toolToDict(_ tool: ToolDefinition) -> [String: Any] {
        [
            "type": "function",
            "function": [
                "name": tool.name,
                "description": tool.description,
                "parameters": tool.parametersAsDictionary
            ]
        ]
    }
}

enum OpenRouterError: LocalizedError {
    case requestFailed
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .requestFailed:
            return "OpenRouter request failed"
        case .invalidResponse:
            return "Invalid response from OpenRouter"
        case .httpError(let statusCode, let message):
            switch statusCode {
            case 401: return "Invalid API key. Please check your OpenRouter API key in Settings."
            case 402: return "Insufficient credits. Please add credits to your OpenRouter account."
            case 429: return "Rate limit exceeded. Please wait a moment and try again."
            case 500...599: return "OpenRouter server error. Please try again later."
            default: return "OpenRouter error (\(statusCode)): \(message)"
            }
        case .cancelled:
            return "Request was cancelled"
        }
    }
}

