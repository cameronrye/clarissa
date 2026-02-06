import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Processes shared content using a lightweight Foundation Models session
/// Handles text summarization, URL content analysis, and image description
actor ShareProcessor {

    /// Process shared text content
    func processText(_ text: String) async -> SharedResult {
        let analysis = await generateAnalysis(
            instruction: "Summarize the following text concisely in 2-3 sentences. Identify the key points.",
            content: text
        )
        return SharedResult(type: .text, originalContent: String(text.prefix(500)), analysis: analysis)
    }

    /// Process a shared URL
    func processURL(_ url: URL) async -> SharedResult {
        // Fetch URL content
        let content: String
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            content = String(data: data, encoding: .utf8) ?? url.absoluteString
        } catch {
            content = url.absoluteString
        }

        let truncated = String(content.prefix(2000))
        let analysis = await generateAnalysis(
            instruction: "Summarize this web content concisely. What is the main topic and key takeaways?",
            content: truncated
        )
        return SharedResult(type: .url, originalContent: url.absoluteString, analysis: analysis)
    }

    /// Process a shared image
    func processImage(_ imageData: Data) async -> SharedResult {
        let analysis = await generateAnalysis(
            instruction: "An image was shared with Clarissa. The user may want to discuss it later.",
            content: "Image shared (\(imageData.count) bytes)"
        )
        return SharedResult(type: .image, originalContent: "Shared image", analysis: analysis)
    }

    /// Generate analysis using a lightweight Foundation Models session
    private func generateAnalysis(instruction: String, content: String) async -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else {
                return fallbackAnalysis(content: content)
            }

            do {
                let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
                let session = LanguageModelSession(
                    model: model,
                    instructions: Instructions(instruction)
                )
                let response = try await session.respond(to: Prompt(content))
                return response.content
            } catch {
                return fallbackAnalysis(content: content)
            }
        }
        #endif
        return fallbackAnalysis(content: content)
    }

    /// Fallback when Foundation Models is unavailable
    private func fallbackAnalysis(content: String) -> String {
        let preview = String(content.prefix(200))
        return "Shared content saved for review: \(preview)..."
    }
}
