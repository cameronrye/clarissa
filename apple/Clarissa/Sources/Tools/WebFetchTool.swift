import Foundation

/// Tool for fetching web content
final class WebFetchTool: ClarissaTool, @unchecked Sendable {
    let name = "web_fetch"
    let description = "Fetch content from a URL and return it as text. Useful for reading web pages, APIs, or documentation."
    let priority = ToolPriority.extended
    let requiresConfirmation = false

    /// Request timeout in seconds
    private let timeout: TimeInterval = ClarissaConstants.networkTimeoutSeconds

    /// Maximum allowed response size
    private let maxResponseSize = ClarissaConstants.maxWebFetchResponseSize

    var parametersSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "url": [
                    "type": "string",
                    "description": "The URL to fetch"
                ],
                "format": [
                    "type": "string",
                    "enum": ["text", "json", "html"],
                    "description": "Response format (default: text)"
                ],
                "maxLength": [
                    "type": "integer",
                    "description": "Maximum response length (default: 10000)"
                ]
            ],
            "required": ["url"]
        ]
    }

    func execute(arguments: String) async throws -> String {
        guard let data = arguments.data(using: .utf8),
              let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let urlString = args["url"] as? String else {
            throw ToolError.invalidArguments("Invalid or missing URL")
        }

        // Validate URL
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw ToolError.invalidArguments("Invalid URL. Only HTTP and HTTPS URLs are supported.")
        }

        let format = args["format"] as? String ?? "text"
        let maxLength = args["maxLength"] as? Int ?? 10000

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("Clarissa/1.0 (AI Assistant)", forHTTPHeaderField: "User-Agent")

        if format == "json" {
            request.setValue("application/json", forHTTPHeaderField: "Accept")
        } else {
            request.setValue("text/html,text/plain,*/*", forHTTPHeaderField: "Accept")
        }

        let (responseData, response) = try await URLSession.shared.data(for: request)

        // Check response size
        guard responseData.count <= maxResponseSize else {
            throw ToolError.executionFailed("Response too large (\(responseData.count / 1024)KB). Maximum allowed is \(maxResponseSize / 1024 / 1024)MB.")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ToolError.executionFailed("Invalid response from server")
        }

        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            let statusMessage = HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw ToolError.executionFailed("HTTP \(httpResponse.statusCode): \(statusMessage)")
        }
        
        var content: String
        
        if format == "json" {
            // Pretty print JSON
            if let json = try? JSONSerialization.jsonObject(with: responseData),
               let prettyData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                content = prettyString
            } else {
                content = String(data: responseData, encoding: .utf8) ?? ""
            }
        } else {
            content = String(data: responseData, encoding: .utf8) ?? ""
            
            // Strip HTML tags for text format
            if format == "text" && content.contains("<") {
                content = stripHTML(content)
            }
        }
        
        // Track original length before truncation
        let originalLength = content.count
        let truncated = content.count > maxLength

        // Truncate if too long
        if truncated {
            content = String(content.prefix(maxLength))
        }

        // Return structured JSON for rich UI display
        let result: [String: Any] = [
            "url": urlString,
            "format": format,
            "content": content,
            "truncated": truncated,
            "characterCount": originalLength
        ]

        let resultData = try JSONSerialization.data(withJSONObject: result)
        return String(data: resultData, encoding: .utf8) ?? content
    }
    
    private func stripHTML(_ html: String) -> String {
        var result = html
        
        // Remove script and style tags with content
        let scriptPattern = "<script[^>]*>[\\s\\S]*?</script>"
        let stylePattern = "<style[^>]*>[\\s\\S]*?</style>"
        
        result = result.replacingOccurrences(of: scriptPattern, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: stylePattern, with: "", options: .regularExpression)
        
        // Remove all other HTML tags
        result = result.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        
        // Clean up whitespace
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

