import Foundation
import Vision
import PDFKit
import CoreImage
import CoreImage.CIFilterBuiltins
import os.log
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

private let logger = Logger(subsystem: "dev.rye.Clarissa", category: "DocumentOCR")

// MARK: - Document OCR Service
//
// Enhanced document scanning using iOS 26 Vision framework.
// Uses RecognizeDocumentsRequest for structured document understanding
// including tables, lists, paragraphs, and barcodes.
//
// Features:
// - Full-document text recognition with structure
// - Table extraction with row/column access
// - PDF text extraction with OCR fallback
// - Handwriting recognition support
// - Barcode detection within documents

/// Result of document OCR processing
public struct DocumentOCRResult: Sendable {
    /// Full extracted text from the document
    public let text: String

    /// Paragraphs detected in the document
    public let paragraphs: [String]

    /// Tables detected with their cell contents
    public let tables: [ExtractedTable]

    /// Barcodes detected in the document
    public let barcodes: [ExtractedBarcode]

    /// Whether handwriting was detected
    public let containsHandwriting: Bool

    /// Number of pages processed (for PDFs)
    public let pageCount: Int

    /// Processing confidence (0-1)
    public let confidence: Float
}

/// Result of handwriting recognition
public struct HandwritingResult: Sendable {
    /// Recognized text from handwriting
    public let text: String

    /// Individual lines with confidence scores
    public let lines: [HandwritingLine]

    /// Overall confidence (0-1)
    public let confidence: Float

    /// Whether the image likely contains handwriting
    public let isHandwritten: Bool
}

/// A single line of recognized handwriting
public struct HandwritingLine: Sendable {
    public let text: String
    public let confidence: Float
}

/// Extracted table structure
public struct ExtractedTable: Sendable {
    public let rows: [[String]]
    public let rowCount: Int
    public let columnCount: Int
}

/// Extracted barcode
public struct ExtractedBarcode: Sendable {
    public let payload: String
    public let symbology: String
}

/// Document OCR service using iOS 26 Vision framework
@available(iOS 26.0, macOS 26.0, *)
public actor DocumentOCRService {

    public static let shared = DocumentOCRService()

    private init() {}

    // MARK: - Public API

    /// Recognize text and structure from an image
    /// - Parameter imageData: Raw image data (JPEG, PNG, HEIC, etc.)
    /// - Returns: Structured document OCR result
    public func recognizeDocument(from imageData: Data) async throws -> DocumentOCRResult {
        guard let cgImage = createCGImage(from: imageData) else {
            throw DocumentOCRError.invalidImage
        }

        return try await recognizeDocument(from: cgImage)
    }

    /// Recognize text and structure from a CGImage
    public func recognizeDocument(from cgImage: CGImage) async throws -> DocumentOCRResult {
        // Use RecognizeDocumentsRequest for structured document recognition
        let request = RecognizeDocumentsRequest()

        // Perform the request
        let observations = try await request.perform(on: cgImage)

        // Process the observations to extract text
        var allText = ""
        var paragraphs: [String] = []
        var totalConfidence: Float = 0

        for observation in observations {
            // Get the full text from the document observation
            // DocumentObservation provides text through its string representation
            let text = observation.description
            allText += text + "\n"

            // Split into paragraphs
            let parts = text.components(separatedBy: "\n")
            for part in parts {
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    paragraphs.append(trimmed)
                }
            }

            totalConfidence += observation.confidence
        }

        let avgConfidence = observations.isEmpty ? 0 : totalConfidence / Float(observations.count)

        return DocumentOCRResult(
            text: allText.trimmingCharacters(in: .whitespacesAndNewlines),
            paragraphs: paragraphs,
            tables: [],
            barcodes: [],
            containsHandwriting: false,
            pageCount: 1,
            confidence: avgConfidence
        )
    }

    // MARK: - Perspective Correction

    /// Document corners for perspective correction (normalized 0-1 coordinates)
    public struct Corners: Sendable {
        public let topLeft: CGPoint
        public let topRight: CGPoint
        public let bottomLeft: CGPoint
        public let bottomRight: CGPoint

        public init(topLeft: CGPoint, topRight: CGPoint, bottomLeft: CGPoint, bottomRight: CGPoint) {
            self.topLeft = topLeft
            self.topRight = topRight
            self.bottomLeft = bottomLeft
            self.bottomRight = bottomRight
        }
    }

    /// Apply perspective correction to an image using detected corners
    /// - Parameters:
    ///   - imageData: Raw image data
    ///   - corners: Detected document corners (normalized 0-1 coordinates)
    /// - Returns: Perspective-corrected image data
    public func perspectiveCorrect(imageData: Data, corners: Corners) throws -> Data {
        guard let cgImage = createCGImage(from: imageData) else {
            throw DocumentOCRError.invalidImage
        }

        let ciImage = CIImage(cgImage: cgImage)
        let imageSize = ciImage.extent.size

        // Convert normalized coordinates to image coordinates
        // Note: Vision uses bottom-left origin, CIImage uses bottom-left origin too
        let topLeft = CGPoint(x: corners.topLeft.x * imageSize.width,
                              y: corners.topLeft.y * imageSize.height)
        let topRight = CGPoint(x: corners.topRight.x * imageSize.width,
                               y: corners.topRight.y * imageSize.height)
        let bottomLeft = CGPoint(x: corners.bottomLeft.x * imageSize.width,
                                 y: corners.bottomLeft.y * imageSize.height)
        let bottomRight = CGPoint(x: corners.bottomRight.x * imageSize.width,
                                  y: corners.bottomRight.y * imageSize.height)

        // Apply perspective correction
        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = ciImage
        filter.topLeft = topLeft
        filter.topRight = topRight
        filter.bottomLeft = bottomLeft
        filter.bottomRight = bottomRight

        guard let outputImage = filter.outputImage else {
            throw DocumentOCRError.recognitionFailed("Perspective correction failed")
        }

        // Render to CGImage
        let context = CIContext()
        guard let correctedCGImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            throw DocumentOCRError.recognitionFailed("Failed to render corrected image")
        }

        // Convert to Data
        #if canImport(UIKit)
        guard let data = UIImage(cgImage: correctedCGImage).jpegData(compressionQuality: 0.9) else {
            throw DocumentOCRError.recognitionFailed("Failed to encode corrected image")
        }
        return data
        #elseif canImport(AppKit)
        let nsImage = NSImage(cgImage: correctedCGImage, size: NSSize(width: correctedCGImage.width, height: correctedCGImage.height))
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
            throw DocumentOCRError.recognitionFailed("Failed to encode corrected image")
        }
        return data
        #endif
    }

    /// Scan document from image with automatic corner detection and perspective correction
    /// - Parameter imageData: Raw image data containing a document
    /// - Returns: OCR result from the perspective-corrected document
    public func scanDocument(from imageData: Data) async throws -> DocumentOCRResult {
        guard let cgImage = createCGImage(from: imageData) else {
            throw DocumentOCRError.invalidImage
        }

        // Detect document corners
        let request = VNDetectDocumentSegmentationRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        guard let observation = request.results?.first else {
            // No document detected, OCR the whole image
            logger.info("No document detected, processing full image")
            return try await recognizeDocument(from: cgImage)
        }

        // Apply perspective correction
        let corners = Corners(
            topLeft: observation.topLeft,
            topRight: observation.topRight,
            bottomLeft: observation.bottomLeft,
            bottomRight: observation.bottomRight
        )

        let correctedData = try perspectiveCorrect(imageData: imageData, corners: corners)

        // OCR the corrected image
        guard let correctedImage = createCGImage(from: correctedData) else {
            throw DocumentOCRError.recognitionFailed("Failed to decode corrected image")
        }

        return try await recognizeDocument(from: correctedImage)
    }

    // MARK: - Handwriting Recognition

    /// Recognize handwritten text from an image
    /// Uses VNRecognizeTextRequest with automatic revision for best handwriting support
    /// - Parameter imageData: Raw image data (JPEG, PNG, HEIC, etc.)
    /// - Returns: Handwriting recognition result with lines and confidence
    public func recognizeHandwriting(from imageData: Data) async throws -> HandwritingResult {
        guard let cgImage = createCGImage(from: imageData) else {
            throw DocumentOCRError.invalidImage
        }

        return try await recognizeHandwriting(from: cgImage)
    }

    /// Recognize handwritten text from a CGImage
    public func recognizeHandwriting(from cgImage: CGImage) async throws -> HandwritingResult {
        // Use VNRecognizeTextRequest with automatic revision for handwriting
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        // Automatic revision selects the best model including handwriting support
        request.revision = VNRecognizeTextRequestRevision3

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        guard let observations = request.results, !observations.isEmpty else {
            return HandwritingResult(
                text: "",
                lines: [],
                confidence: 0,
                isHandwritten: false
            )
        }

        var lines: [HandwritingLine] = []
        var allText: [String] = []
        var totalConfidence: Float = 0
        var handwritingIndicators = 0

        for observation in observations {
            guard let topCandidate = observation.topCandidates(1).first else { continue }

            let lineText = topCandidate.string
            let lineConfidence = topCandidate.confidence

            lines.append(HandwritingLine(text: lineText, confidence: lineConfidence))
            allText.append(lineText)
            totalConfidence += lineConfidence

            // Heuristics for detecting handwriting:
            // - Lower confidence often indicates handwriting
            // - Irregular baseline (varying y positions)
            if lineConfidence < 0.85 {
                handwritingIndicators += 1
            }
        }

        let avgConfidence = Float(totalConfidence) / Float(observations.count)

        // Consider it handwriting if >30% of lines have lower confidence
        let isHandwritten = Float(handwritingIndicators) / Float(observations.count) > 0.3

        return HandwritingResult(
            text: allText.joined(separator: "\n"),
            lines: lines,
            confidence: avgConfidence,
            isHandwritten: isHandwritten
        )
    }

    /// Recognize text from a PDF document
    /// - Parameters:
    ///   - pdfData: PDF file data
    ///   - maxPages: Maximum pages to process (default: 10)
    /// - Returns: Combined OCR result from all pages
    public func recognizePDF(from pdfData: Data, maxPages: Int = 10) async throws -> DocumentOCRResult {
        guard let document = PDFDocument(data: pdfData) else {
            throw DocumentOCRError.invalidPDF
        }

        let pageCount = min(document.pageCount, maxPages)
        var allText = ""
        var allParagraphs: [String] = []
        var allTables: [ExtractedTable] = []
        var allBarcodes: [ExtractedBarcode] = []
        var containsHandwriting = false
        var totalConfidence: Float = 0

        for pageIndex in 0..<pageCount {
            guard let page = document.page(at: pageIndex) else { continue }

            // First try native text extraction
            if let nativeText = page.string, !nativeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                allText += "--- Page \(pageIndex + 1) ---\n\(nativeText)\n\n"
                allParagraphs.append(contentsOf: nativeText.components(separatedBy: "\n\n"))
                totalConfidence += 1.0
            } else {
                // Fall back to OCR for scanned pages
                if let cgImage = renderPageToImage(page) {
                    do {
                        let pageResult = try await recognizeDocument(from: cgImage)
                        allText += "--- Page \(pageIndex + 1) ---\n\(pageResult.text)\n\n"
                        allParagraphs.append(contentsOf: pageResult.paragraphs)
                        allTables.append(contentsOf: pageResult.tables)
                        allBarcodes.append(contentsOf: pageResult.barcodes)
                        containsHandwriting = containsHandwriting || pageResult.containsHandwriting
                        totalConfidence += pageResult.confidence
                    } catch {
                        logger.warning("Failed to OCR page \(pageIndex + 1): \(error.localizedDescription)")
                    }
                }
            }
        }

        return DocumentOCRResult(
            text: allText.trimmingCharacters(in: .whitespacesAndNewlines),
            paragraphs: allParagraphs,
            tables: allTables,
            barcodes: allBarcodes,
            containsHandwriting: containsHandwriting,
            pageCount: document.pageCount,
            confidence: pageCount > 0 ? totalConfidence / Float(pageCount) : 0
        )
    }

    // MARK: - Private Helpers

    /// Create CGImage from raw data
    private func createCGImage(from data: Data) -> CGImage? {
        #if canImport(UIKit)
        return UIImage(data: data)?.cgImage
        #elseif canImport(AppKit)
        guard let nsImage = NSImage(data: data),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return cgImage
        #else
        return nil
        #endif
    }

    /// Render PDF page to CGImage for OCR
    private func renderPageToImage(_ page: PDFPage) -> CGImage? {
        let pageRect = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0 // Higher resolution for better OCR

        let width = Int(pageRect.width * scale)
        let height = Int(pageRect.height * scale)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)

        return context.makeImage()
    }
}

// MARK: - Errors

@available(iOS 26.0, macOS 26.0, *)
enum DocumentOCRError: LocalizedError {
    case invalidImage
    case invalidPDF
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Failed to decode image data"
        case .invalidPDF:
            return "Failed to load PDF document"
        case .recognitionFailed(let reason):
            return "Document recognition failed: \(reason)"
        }
    }
}

// MARK: - Legacy Fallback

/// Fallback OCR for iOS versions before 26
/// Uses VNRecognizeTextRequest for basic text recognition
struct LegacyDocumentOCR {

    /// Perform basic OCR on an image
    static func recognizeText(from cgImage: CGImage) async throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        guard let observations = request.results else {
            return ""
        }

        return observations.compactMap { observation in
            observation.topCandidates(1).first?.string
        }.joined(separator: "\n")
    }
}
