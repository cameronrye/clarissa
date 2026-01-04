import Foundation
import os.log

/// Maps technical errors to user-friendly messages
enum ErrorMapper {

    private static let logger = Logger(subsystem: "dev.rye.clarissa", category: "ErrorMapper")

    /// Error severity levels for reporting
    enum Severity: String {
        case info
        case warning
        case error
        case critical
    }

    /// Structured error info for reporting
    struct ErrorInfo {
        let userMessage: String
        let technicalMessage: String
        let severity: Severity
        let isRecoverable: Bool
        let suggestedAction: String?
    }

    /// Get detailed error information for reporting and display
    static func analyze(_ error: Error) -> ErrorInfo {
        let userMessage = userFriendlyMessage(for: error)
        let technicalMessage = String(describing: error)
        let severity = determineSeverity(for: error)
        let isRecoverable = isErrorRecoverable(error)
        let suggestedAction = suggestAction(for: error)

        // Log the error with appropriate level
        logError(error, severity: severity)

        return ErrorInfo(
            userMessage: userMessage,
            technicalMessage: technicalMessage,
            severity: severity,
            isRecoverable: isRecoverable,
            suggestedAction: suggestedAction
        )
    }

    /// Convert any error to a user-friendly message with guidance
    static func userFriendlyMessage(for error: Error) -> String {
        // Handle specific error types
        if let agentError = error as? AgentError {
            return mapAgentError(agentError)
        }

        if let toolError = error as? ToolError {
            return mapToolError(toolError)
        }

        if let foundationError = error as? FoundationModelsError {
            return mapFoundationModelsError(foundationError)
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

    private static func mapFoundationModelsError(_ error: FoundationModelsError) -> String {
        switch error {
        case .notAvailable:
            return "Apple Intelligence is not available on this device."
        case .deviceNotEligible:
            return "This device doesn't support Apple Intelligence. Requires iPhone 15 Pro or later."
        case .appleIntelligenceNotEnabled:
            return "Please enable Apple Intelligence in Settings > Apple Intelligence & Siri."
        case .modelNotReady:
            return "Apple Intelligence is still setting up. Please wait a moment and try again."
        case .toolExecutionFailed(let message):
            // Extract useful info from the message
            if message.lowercased().contains("location") {
                return "Could not access location. Please check location permissions in Settings."
            }
            if message.lowercased().contains("weather") {
                return "Unable to get weather information. Please try again."
            }
            return "An error occurred: \(message)"
        case .guardrailViolation:
            return "I can't help with that request. Please try asking something else."
        case .refusal(let reason):
            return "I can't help with that: \(reason)"
        case .contextWindowExceeded:
            return "The conversation is too long. Please start a new chat."
        case .unsupportedLanguage(let locale):
            return "Language '\(locale)' is not currently supported. Please try in English."
        case .rateLimited:
            return "Too many requests. Please wait a moment and try again."
        case .concurrentRequests:
            return "Already processing a request. Please wait for it to complete."
        case .generationFailed(let message):
            // Provide more helpful messages for common generation failures
            if message.lowercased().contains("decode") {
                return "The AI had trouble processing that request. Please try again with a simpler question."
            }
            return "Something went wrong with the AI. Please try again."
        }
    }

    // MARK: - Error Analysis Helpers

    private static func determineSeverity(for error: Error) -> Severity {
        if let agentError = error as? AgentError {
            switch agentError {
            case .maxIterationsReached:
                return .warning
            case .noProvider:
                return .error
            case .toolNotFound:
                return .warning
            case .toolExecutionFailed:
                return .warning
            }
        }

        if let foundationError = error as? FoundationModelsError {
            switch foundationError {
            case .notAvailable, .deviceNotEligible:
                return .critical
            case .appleIntelligenceNotEnabled, .modelNotReady:
                return .error
            case .guardrailViolation, .refusal:
                return .info
            case .rateLimited, .concurrentRequests:
                return .warning
            default:
                return .error
            }
        }

        if error is URLError {
            return .warning
        }

        return .error
    }

    private static func isErrorRecoverable(_ error: Error) -> Bool {
        if let foundationError = error as? FoundationModelsError {
            switch foundationError {
            case .notAvailable, .deviceNotEligible:
                return false
            case .rateLimited, .concurrentRequests, .modelNotReady:
                return true
            default:
                return true
            }
        }

        if error is URLError {
            return true
        }

        if let agentError = error as? AgentError {
            switch agentError {
            case .noProvider:
                return false
            default:
                return true
            }
        }

        return true
    }

    private static func suggestAction(for error: Error) -> String? {
        if let foundationError = error as? FoundationModelsError {
            switch foundationError {
            case .appleIntelligenceNotEnabled:
                return "Open Settings to enable Apple Intelligence"
            case .deviceNotEligible:
                return "This feature requires iPhone 15 Pro or later"
            case .rateLimited:
                return "Wait a few seconds and try again"
            default:
                return nil
            }
        }

        if let agentError = error as? AgentError {
            switch agentError {
            case .noProvider:
                return "Configure an AI provider in Settings"
            default:
                return nil
            }
        }

        if let toolError = error as? ToolError {
            switch toolError {
            case .permissionDenied:
                return "Open Settings to grant permission"
            default:
                return nil
            }
        }

        return nil
    }

    private static func logError(_ error: Error, severity: Severity) {
        let message = "Error: \(String(describing: error))"

        switch severity {
        case .info:
            logger.info("\(message)")
        case .warning:
            logger.warning("\(message)")
        case .error:
            logger.error("\(message)")
        case .critical:
            logger.critical("\(message)")
        }
    }
}

