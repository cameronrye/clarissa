import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif
import Vision
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Foundation Models Image Analyzer
//
// Enhanced image analysis using Foundation Models' multimodal capabilities (iOS 26+).
// The on-device model includes a 300M parameter vision encoder (ViTDet-L) that can
// understand images alongside text, providing natural language descriptions.
//
// This supplements the Vision framework's structured extraction with AI understanding.

/// Image analysis result combining Vision framework and Foundation Models
@available(iOS 26.0, macOS 26.0, *)
public struct EnhancedImageAnalysis: Sendable {
    /// Natural language description of the image content
    public let description: String

    /// Text extracted via OCR
    public let extractedText: String

    /// Detected objects/classifications from Vision
    public let classifications: [String]

    /// Number of faces detected
    public let faceCount: Int

    /// Whether a document was detected
    public let hasDocument: Bool

    /// Key entities extracted from the image
    public let entities: [String]

    /// Suggested actions based on image content
    public let suggestedActions: [String]

    /// Compact context for LLM consumption
    public var contextString: String {
        var parts: [String] = []

        if !description.isEmpty {
            parts.append("Description: \(description)")
        }

        if !extractedText.isEmpty {
            let truncated = extractedText.count > 1000
                ? String(extractedText.prefix(1000)) + "..."
                : extractedText
            parts.append("Text content: \(truncated)")
        }

        if !classifications.isEmpty {
            parts.append("Contains: \(classifications.joined(separator: ", "))")
        }

        if faceCount > 0 {
            parts.append("Faces: \(faceCount)")
        }

        if !entities.isEmpty {
            parts.append("Key elements: \(entities.joined(separator: ", "))")
        }

        if parts.isEmpty {
            return "[No notable content detected]"
        }

        return "[Image Analysis]\n\(parts.joined(separator: "\n"))"
    }
}

/// Result of multi-image comparison analysis
@available(iOS 26.0, macOS 26.0, *)
public struct MultiImageAnalysis: Sendable {
    /// Overall summary describing the collection of images
    public let summary: String

    /// Individual analysis for each image
    public let imageAnalyses: [EnhancedImageAnalysis]

    /// Similarities found across images
    public let similarities: [String]

    /// Differences found between images
    public let differences: [String]

    /// Detected relationship type
    public let relationship: String

    /// Combined suggested actions
    public let suggestedActions: [String]

    /// Compact context for LLM consumption
    public var contextString: String {
        var parts: [String] = []

        parts.append("Summary: \(summary)")
        parts.append("Image count: \(imageAnalyses.count)")

        if !relationship.isEmpty {
            parts.append("Relationship: \(relationship)")
        }

        if !similarities.isEmpty {
            parts.append("Similarities: \(similarities.joined(separator: ", "))")
        }

        if !differences.isEmpty {
            parts.append("Differences: \(differences.joined(separator: ", "))")
        }

        return "[Multi-Image Analysis]\n\(parts.joined(separator: "\n"))"
    }
}

#if canImport(FoundationModels)

/// Guided generation types for image understanding
@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "Image content analysis")
struct ImageUnderstanding {
    @Guide(description: "Brief description of what the image shows (1-2 sentences)")
    var description: String

    @Guide(description: "Key objects, people, or elements visible")
    var keyElements: [String]

    @Guide(description: "Suggested actions the user might want (e.g., 'add to contacts', 'create event')")
    var suggestedActions: [String]

    @Guide(description: "Overall category: photo, screenshot, document, chart, diagram, or other")
    var category: String
}

/// Guided generation for multi-image comparison
@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "Multi-image comparison and relationship analysis")
struct MultiImageUnderstanding {
    @Guide(description: "Summary of what the images show together")
    var overallSummary: String

    @Guide(description: "Key similarities between the images")
    var similarities: [String]

    @Guide(description: "Notable differences between the images")
    var differences: [String]

    @Guide(description: "Relationship between images: sequence, comparison, before-after, collection, or unrelated")
    var relationship: String

    @Guide(description: "Suggested actions based on all images")
    var suggestedActions: [String]
}

/// Enhanced image analyzer using Foundation Models for natural language understanding
@available(iOS 26.0, macOS 26.0, *)
@MainActor
public final class FoundationModelsImageAnalyzer {

    /// Shared instance
    public static let shared = FoundationModelsImageAnalyzer()

    private let visionProcessor = ImagePreProcessor()

    private init() {}

    /// Analyze image with both Vision framework and Foundation Models
    /// - Parameter imageData: Raw image data (JPEG, PNG, HEIC, etc.)
    /// - Returns: Enhanced analysis with AI-generated description
    public func analyze(imageData: Data) async -> EnhancedImageAnalysis {
        // First, get structured extraction from Vision framework
        let visionResult = await visionProcessor.process(imageData: imageData)

        // Build context for Foundation Models
        var contextParts: [String] = []

        if !visionResult.extractedText.isEmpty {
            contextParts.append("OCR text: \(visionResult.extractedText.prefix(500))")
        }
        if !visionResult.classifications.isEmpty {
            contextParts.append("Detected: \(visionResult.classifications.joined(separator: ", "))")
        }
        if visionResult.faceCount > 0 {
            contextParts.append("Faces: \(visionResult.faceCount)")
        }
        if visionResult.hasDocument {
            contextParts.append("Document detected")
        }

        let visionContext = contextParts.isEmpty ? "General image" : contextParts.joined(separator: "; ")

        // Use Foundation Models to generate natural language understanding
        do {
            let understanding = try await generateUnderstanding(visionContext: visionContext)

            return EnhancedImageAnalysis(
                description: understanding.description,
                extractedText: visionResult.extractedText,
                classifications: visionResult.classifications,
                faceCount: visionResult.faceCount,
                hasDocument: visionResult.hasDocument,
                entities: understanding.keyElements,
                suggestedActions: understanding.suggestedActions
            )
        } catch {
            // Fall back to Vision-only results
            return EnhancedImageAnalysis(
                description: "",
                extractedText: visionResult.extractedText,
                classifications: visionResult.classifications,
                faceCount: visionResult.faceCount,
                hasDocument: visionResult.hasDocument,
                entities: [],
                suggestedActions: []
            )
        }
    }

    /// Generate natural language understanding using Foundation Models
    private func generateUnderstanding(visionContext: String) async throws -> ImageUnderstanding {
        let session = LanguageModelSession(
            instructions: Instructions("""
                You are analyzing an image. Based on the Vision framework analysis provided,
                generate a natural language description and identify key elements.
                Be concise and helpful. Suggest relevant actions the user might want to take.
                """)
        )

        let result = try await session.respond(
            to: Prompt("Image analysis data: \(visionContext)\n\nDescribe this image and suggest actions."),
            generating: ImageUnderstanding.self
        )

        return result.content
    }

    /// Quick description generation for an image
    /// - Parameter imageData: Raw image data
    /// - Returns: Brief natural language description
    public func describe(imageData: Data) async -> String {
        let analysis = await analyze(imageData: imageData)
        return analysis.description.isEmpty
            ? analysis.contextString
            : analysis.description
    }

    // MARK: - Multi-Image Analysis

    /// Analyze multiple images and understand their relationships
    /// - Parameters:
    ///   - images: Array of image data (2-5 images recommended)
    ///   - prompt: Optional user prompt for specific comparison focus
    /// - Returns: Multi-image analysis with comparisons and relationships
    public func analyzeMultiple(images: [Data], prompt: String? = nil) async -> MultiImageAnalysis {
        // Limit to 5 images
        let limitedImages = Array(images.prefix(5))

        // Analyze each image individually
        var imageAnalyses: [EnhancedImageAnalysis] = []
        var visionContexts: [String] = []

        for (index, imageData) in limitedImages.enumerated() {
            let analysis = await analyze(imageData: imageData)
            imageAnalyses.append(analysis)

            // Build context string for this image
            var parts: [String] = []
            parts.append("Image \(index + 1):")
            if !analysis.description.isEmpty {
                parts.append("  Description: \(analysis.description)")
            }
            if !analysis.extractedText.isEmpty {
                parts.append("  Text: \(String(analysis.extractedText.prefix(200)))")
            }
            if !analysis.classifications.isEmpty {
                parts.append("  Contains: \(analysis.classifications.joined(separator: ", "))")
            }
            if analysis.faceCount > 0 {
                parts.append("  Faces: \(analysis.faceCount)")
            }
            visionContexts.append(parts.joined(separator: "\n"))
        }

        // Use Foundation Models to understand relationships
        do {
            let understanding = try await generateMultiImageUnderstanding(
                contexts: visionContexts,
                prompt: prompt
            )

            return MultiImageAnalysis(
                summary: understanding.overallSummary,
                imageAnalyses: imageAnalyses,
                similarities: understanding.similarities,
                differences: understanding.differences,
                relationship: understanding.relationship,
                suggestedActions: understanding.suggestedActions
            )
        } catch {
            // Fall back to basic analysis without AI comparison
            return MultiImageAnalysis(
                summary: "Collection of \(imageAnalyses.count) images",
                imageAnalyses: imageAnalyses,
                similarities: [],
                differences: [],
                relationship: "collection",
                suggestedActions: []
            )
        }
    }

    /// Generate multi-image understanding using Foundation Models
    private func generateMultiImageUnderstanding(
        contexts: [String],
        prompt: String?
    ) async throws -> MultiImageUnderstanding {
        let session = LanguageModelSession(
            instructions: Instructions("""
                You are analyzing multiple images together. Based on the Vision framework analysis provided,
                identify relationships, similarities, and differences between the images.
                Be concise and helpful. Suggest relevant actions based on the collection.
                """)
        )

        var promptText = "Image analyses:\n\(contexts.joined(separator: "\n\n"))"
        if let userPrompt = prompt {
            promptText += "\n\nUser question: \(userPrompt)"
        }
        promptText += "\n\nAnalyze these images together and describe their relationships."

        let result = try await session.respond(
            to: Prompt(promptText),
            generating: MultiImageUnderstanding.self
        )

        return result.content
    }

    /// Compare exactly two images for before/after or difference detection
    /// - Parameters:
    ///   - before: First image data
    ///   - after: Second image data
    /// - Returns: Multi-image analysis focused on changes
    public func compareBeforeAfter(before: Data, after: Data) async -> MultiImageAnalysis {
        return await analyzeMultiple(
            images: [before, after],
            prompt: "Compare these two images. What changed between the first and second image?"
        )
    }
}

#endif
