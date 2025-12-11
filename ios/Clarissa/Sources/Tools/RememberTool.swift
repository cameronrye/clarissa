import Foundation

// MARK: - Typed Arguments

/// Typed arguments for RememberTool using Codable
struct RememberArguments: Codable {
    let content: String
}

/// Tool for storing long-term memories
final class RememberTool: ClarissaTool, @unchecked Sendable {
    let name = "remember"
    let description = "Store important information in long-term memory. Use this to remember user preferences, important facts, or context that should persist across conversations."
    let priority = ToolPriority.core
    let requiresConfirmation = false

    var parametersSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "content": [
                    "type": "string",
                    "description": "The information to remember. Be concise but include relevant context."
                ]
            ],
            "required": ["content"]
        ]
    }

    func execute(arguments: String) async throws -> String {
        guard let data = arguments.data(using: .utf8) else {
            throw ToolError.invalidArguments("Invalid argument encoding")
        }

        let args: RememberArguments
        do {
            args = try JSONDecoder().decode(RememberArguments.self, from: data)
        } catch {
            throw ToolError.invalidArguments("Missing content parameter")
        }

        let content = args.content
        
        // Store the memory
        await MemoryManager.shared.add(content)
        
        let response: [String: Any] = [
            "success": true,
            "message": "Memory stored successfully",
            "content": content
        ]
        
        let responseData = try JSONSerialization.data(withJSONObject: response)
        return String(data: responseData, encoding: .utf8) ?? "{}"
    }
}

