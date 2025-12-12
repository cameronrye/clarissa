import Foundation

/// Maps technical errors to user-friendly messages
enum ErrorMapper {

    /// Convert any error to a user-friendly message with guidance
    static func userFriendlyMessage(for error: Error) -> String {
        // Handle specific error types
        if let agentError = error as? AgentError {
            return mapAgentError(agentError)
        }

        if let toolError = error as? ToolError {
            return mapToolError(toolError)
        }

        if let urlError = error as? URLError {
            return mapURLError(urlError)
        }

        // Handle common error patterns by description
        let description = error.localizedDescription.lowercased()

        if description.contains("network") || description.contains("internet") {
            return "Unable to connect. Please check your internet connection and try again."
        }

        if description.contains("timeout") {
            return "The request took too long. Please try again."
        }

        if description.contains("unauthorized") || description.contains("401") {
            return "Authentication failed. Please check your API key in Settings."
        }

        if description.contains("rate limit") || description.contains("429") {
            return "Too many requests. Please wait a moment and try again."
        }

        if description.contains("server") || description.contains("500") || description.contains("502") || description.contains("503") {
            return "The service is temporarily unavailable. Please try again later."
        }

        if description.contains("permission") || description.contains("denied") {
            return "Permission denied. Please check app permissions in Settings."
        }

        // Generic fallback - but still helpful
        return "Something went wrong. Please try again."
    }

    private static func mapAgentError(_ error: AgentError) -> String {
        switch error {
        case .maxIterationsReached:
            return "I got stuck in a loop while processing your request. Please try rephrasing your question."
        case .noProvider:
            return "No AI provider is configured. Please set up a provider in Settings."
        case .toolNotFound(let name):
            return "The '\(name)' feature is not available. Please try a different request."
        case .toolExecutionFailed(let name, _):
            return "The \(name) feature encountered an error. Please try again."
        }
    }

    private static func mapToolError(_ error: ToolError) -> String {
        switch error {
        case .notAvailable(let reason):
            return "This feature is not available: \(reason)"
        case .permissionDenied(let permission):
            return "Permission needed: Please enable \(permission) access in Settings."
        case .invalidArguments:
            return "I couldn't understand that request. Please try rephrasing."
        case .executionFailed(let reason):
            if reason.lowercased().contains("network") {
                return "Unable to connect. Please check your internet connection."
            }
            return "An error occurred: \(reason)"
        }
    }

    private static func mapURLError(_ error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet:
            return "You're offline. Please check your internet connection."
        case .timedOut:
            return "The request took too long. Please try again."
        case .cannotFindHost, .cannotConnectToHost:
            return "Unable to reach the server. Please check your connection."
        case .networkConnectionLost:
            return "Connection lost. Please try again."
        case .secureConnectionFailed:
            return "Secure connection failed. Please try again."
        default:
            return "Network error. Please check your connection and try again."
        }
    }
}

