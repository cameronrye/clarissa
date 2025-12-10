import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Provider using Apple's on-device Foundation Models
@available(iOS 26.0, macOS 26.0, *)
final class FoundationModelsProvider: LLMProvider, @unchecked Sendable {
    let name = "Apple Intelligence"
    let maxTools = 10

    /// Marker for tool calls in the response
    private let toolCallStart = "<tool_call>"
    private let toolCallEnd = "</tool_call>"

    #if canImport(FoundationModels)
    private var session: LanguageModelSession?
    #endif

    var isAvailable: Bool {
        get async {
            #if canImport(FoundationModels)
            switch SystemLanguageModel.default.availability {
            case .available:
                return true
            case .unavailable:
                return false
            }
            #else
            return false
            #endif
        }
    }

    #if canImport(FoundationModels)
    /// Create session with system prompt including tool definitions
    private func createSession(systemPrompt: String?, tools: [ToolDefinition]) -> LanguageModelSession {
        var fullPrompt = systemPrompt ?? ""

        // Add tool definitions if we have tools
        if !tools.isEmpty {
            fullPrompt += "\n\n" + buildToolInstructions(tools: tools)
        }

        return LanguageModelSession {
            fullPrompt
        }
    }
    #endif

    /// Build tool instructions for the system prompt
    private func buildToolInstructions(tools: [ToolDefinition]) -> String {
        var instructions = """
        ## Available Tools

        You have access to the following tools. To use a tool, respond with:
        <tool_call>
        {"name": "tool_name", "arguments": {"param1": "value1"}}
        </tool_call>

        IMPORTANT: When you need to use a tool, output ONLY the tool_call block. Do not include any other text before or after it. Wait for the tool result before continuing.

        Tools:
        """

        for tool in tools {
            instructions += "\n\n### \(tool.name)\n"
            instructions += "\(tool.description)\n"
            instructions += "Parameters: "
            if let jsonData = try? JSONSerialization.data(withJSONObject: tool.parameters, options: [.sortedKeys]),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                instructions += jsonString
            }
        }

        return instructions
    }

    /// Parse tool calls from the response content
    private func parseToolCalls(from content: String) -> [ToolCall] {
        var toolCalls: [ToolCall] = []
        var searchRange = content.startIndex..<content.endIndex

        while let startRange = content.range(of: toolCallStart, range: searchRange),
              let endRange = content.range(of: toolCallEnd, range: startRange.upperBound..<content.endIndex) {

            let jsonString = String(content[startRange.upperBound..<endRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let jsonData = jsonString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let name = json["name"] as? String {

                // Get arguments as JSON string
                var argumentsString = "{}"
                if let arguments = json["arguments"] {
                    if let argsData = try? JSONSerialization.data(withJSONObject: arguments),
                       let argsStr = String(data: argsData, encoding: .utf8) {
                        argumentsString = argsStr
                    }
                }

                toolCalls.append(ToolCall(
                    id: UUID().uuidString,
                    name: name,
                    arguments: argumentsString
                ))
            }

            searchRange = endRange.upperBound..<content.endIndex
        }

        return toolCalls
    }

    /// Remove tool call markers from content for display
    private func cleanContent(_ content: String) -> String {
        var result = content
        var searchRange = result.startIndex..<result.endIndex

        while let startRange = result.range(of: toolCallStart, range: searchRange),
              let endRange = result.range(of: toolCallEnd, range: startRange.upperBound..<result.endIndex) {
            result.removeSubrange(startRange.lowerBound...endRange.upperBound)
            searchRange = result.startIndex..<result.endIndex
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func streamComplete(
        messages: [Message],
        tools: [ToolDefinition]
    ) -> AsyncThrowingStream<StreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                #if canImport(FoundationModels)
                do {
                    // Extract system prompt
                    let systemPrompt = messages.first { $0.role == .system }?.content

                    // Create session with system prompt AND tool definitions
                    let session = createSession(systemPrompt: systemPrompt, tools: tools)
                    self.session = session

                    // Build the user prompt from messages (excluding system)
                    let prompt = buildPrompt(from: messages)

                    // Stream response
                    let stream = session.streamResponse(to: prompt)

                    var lastContent = ""
                    var fullContent = ""

                    for try await partial in stream {
                        let currentContent = partial.content
                        fullContent = currentContent

                        // Get new content delta (only non-tool-call content)
                        if currentContent.count > lastContent.count {
                            let delta = String(currentContent.dropFirst(lastContent.count))

                            // Only yield content that's not inside a tool call block
                            if !delta.contains(toolCallStart) && !lastContent.contains(toolCallStart) {
                                continuation.yield(StreamChunk(
                                    content: delta,
                                    toolCalls: nil,
                                    isComplete: false
                                ))
                            }
                        }
                        lastContent = currentContent
                    }

                    // Parse any tool calls from the complete response
                    let toolCalls = parseToolCalls(from: fullContent)

                    // If we have tool calls, clean the content
                    let finalContent = toolCalls.isEmpty ? nil : cleanContent(fullContent)
                    if let content = finalContent, !content.isEmpty {
                        // Yield any remaining content before tool calls
                        continuation.yield(StreamChunk(
                            content: content,
                            toolCalls: nil,
                            isComplete: false
                        ))
                    }

                    continuation.yield(StreamChunk(
                        content: nil,
                        toolCalls: toolCalls.isEmpty ? nil : toolCalls,
                        isComplete: true
                    ))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
                #else
                continuation.finish(throwing: FoundationModelsError.notAvailable)
                #endif
            }
        }
    }

    private func buildPrompt(from messages: [Message]) -> String {
        var prompt = ""

        for message in messages {
            switch message.role {
            case .system:
                // System prompt is handled via session instructions
                continue
            case .user:
                prompt += "User: \(message.content)\n\n"
            case .assistant:
                prompt += "Assistant: \(message.content)\n\n"
            case .tool:
                if let name = message.toolName {
                    prompt += "Tool Result (\(name)): \(message.content)\n\n"
                }
            }
        }

        return prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Reset the session for a new conversation
    func resetSession() {
        #if canImport(FoundationModels)
        session = nil
        #endif
    }
}

enum FoundationModelsError: LocalizedError {
    case notAvailable
    case toolExecutionFailed(String)
    case modelNotReady

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Apple Intelligence is not available on this device. Please ensure you have iOS 26+ and Apple Intelligence enabled."
        case .toolExecutionFailed(let message):
            return "Tool execution failed: \(message)"
        case .modelNotReady:
            return "Apple Intelligence model is not ready. Please try again."
        }
    }
}

