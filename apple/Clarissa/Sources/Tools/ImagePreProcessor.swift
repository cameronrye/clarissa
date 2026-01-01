import Foundation
import Vision
import PDFKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Pre-processes images and PDFs BEFORE involving the LLM.
/// This is critical for Apple Foundation Models which have a 4,096 token limit.
/// Instead of passing base64 data (~100KB+ = 25,000+ tokens), we extract text
/// and metadata (~500 chars = ~150 tokens) to stay within context limits.
///
/// Usage:
///   let processor = ImagePreProcessor()
///   let result = await processor.process(imageData: data)
///   // result.contextString contains ~500 chars of extracted text/metadata
///   // Pass this to the LLM, NOT the base64 data
final class ImagePreProcessor: Sendable {
    
    /// Result of pre-processing an image or PDF
    struct ProcessingResult: Sendable {
        let extractedText: String
        let classifications: [String]
        let faceCount: Int
        let hasDocument: Bool
        let pageCount: Int  // For PDFs
        let error: String?
        
        /// Compact context string for the LLM (typically 200-500 chars)
        var contextString: String {
            var parts: [String] = []
            
            if let error = error {
                return "[Image processing error: \(error)]"
            }
            
            if pageCount > 0 {
                parts.append("PDF with \(pageCount) page\(pageCount == 1 ? "" : "s")")
            }
            
            if !extractedText.isEmpty {
                // Truncate text to keep context reasonable
                let maxTextLength = 1500
                let truncatedText = extractedText.count > maxTextLength 
                    ? String(extractedText.prefix(maxTextLength)) + "..."
                    : extractedText
                parts.append("Text content: \(truncatedText)")
            }
            
            if !classifications.isEmpty {
                parts.append("Contains: \(classifications.joined(separator: ", "))")
            }
            
            if faceCount > 0 {
                parts.append("Faces detected: \(faceCount)")
            }
            
            if hasDocument {
                parts.append("Document detected in image")
            }
            
            if parts.isEmpty {
                return "[Image analyzed - no text or notable content detected]"
            }
            
            return "[Image Analysis]\n\(parts.joined(separator: "\n"))"
        }
    }
    
    // MARK: - Public Methods
    
    /// Process image data and extract text/metadata
    func process(imageData: Data) async -> ProcessingResult {
        guard let cgImage = cgImageFromData(imageData) else {
            return ProcessingResult(
                extractedText: "",
                classifications: [],
                faceCount: 0,
                hasDocument: false,
                pageCount: 0,
                error: "Failed to decode image"
            )
        }
        
        return await processImage(cgImage)
    }
    
    /// Process a PDF and extract text/metadata
    func process(pdfData: Data) async -> ProcessingResult {
        guard let document = PDFDocument(data: pdfData) else {
            return ProcessingResult(
                extractedText: "",
                classifications: [],
                faceCount: 0,
                hasDocument: false,
                pageCount: 0,
                error: "Failed to decode PDF"
            )
        }
        
        return await processPDF(document)
    }
    
    // MARK: - Image Processing
    
    private func processImage(_ cgImage: CGImage) async -> ProcessingResult {
        // Run OCR, classification, and face detection in parallel
        async let ocrResult = performOCR(on: cgImage)
        async let classifyResult = performClassification(on: cgImage)
        async let faceResult = detectFaces(in: cgImage)
        async let docResult = detectDocument(in: cgImage)
        
        let (text, classifications, faceCount, hasDocument) = await (
            ocrResult, classifyResult, faceResult, docResult
        )
        
        return ProcessingResult(
            extractedText: text,
            classifications: classifications,
            faceCount: faceCount,
            hasDocument: hasDocument,
            pageCount: 0,
            error: nil
        )
    }
    
    private func performOCR(on image: CGImage) async -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        
        do {
            try handler.perform([request])
            guard let observations = request.results else { return "" }
            return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        } catch {
            return ""
        }
    }
    
    private func performClassification(on image: CGImage) async -> [String] {
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        do {
            try handler.perform([request])
            guard let observations = request.results else { return [] }
            // Return top 5 with confidence > 20%
            return observations
                .filter { $0.confidence > 0.2 }
                .prefix(5)
                .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
        } catch {
            return []
        }
    }

    private func detectFaces(in image: CGImage) async -> Int {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        do {
            try handler.perform([request])
            return request.results?.count ?? 0
        } catch {
            return 0
        }
    }

    private func detectDocument(in image: CGImage) async -> Bool {
        let request = VNDetectDocumentSegmentationRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        do {
            try handler.perform([request])
            return request.results?.first != nil
        } catch {
            return false
        }
    }

    // MARK: - PDF Processing

    private func processPDF(_ document: PDFDocument) async -> ProcessingResult {
        let pageCount = document.pageCount
        var allText = ""
        let maxPagesToProcess = min(pageCount, 5)  // Limit to first 5 pages

        for i in 0..<maxPagesToProcess {
            guard let page = document.page(at: i) else { continue }

            // First try native text extraction
            if let pageText = page.string, !pageText.isEmpty {
                allText += "Page \(i + 1): \(pageText)\n"
            } else {
                // Fall back to OCR for scanned PDFs
                if let cgImage = renderPageToImage(page) {
                    let ocrText = await performOCR(on: cgImage)
                    if !ocrText.isEmpty {
                        allText += "Page \(i + 1) (OCR): \(ocrText)\n"
                    }
                }
            }
        }

        return ProcessingResult(
            extractedText: allText,
            classifications: [],
            faceCount: 0,
            hasDocument: true,
            pageCount: pageCount,
            error: nil
        )
    }

    private func renderPageToImage(_ page: PDFPage) -> CGImage? {
        let pageRect = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0  // 2x for better OCR

        #if canImport(UIKit)
        let renderer = UIGraphicsImageRenderer(size: CGSize(
            width: pageRect.width * scale,
            height: pageRect.height * scale
        ))
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: renderer.format.bounds.size))
            context.cgContext.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context.cgContext)
        }
        return image.cgImage
        #elseif canImport(AppKit)
        let image = NSImage(size: NSSize(
            width: pageRect.width * scale,
            height: pageRect.height * scale
        ))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        if let context = NSGraphicsContext.current?.cgContext {
            context.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context)
        }
        image.unlockFocus()
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #endif
    }

    // MARK: - Image Decoding

    private func cgImageFromData(_ data: Data) -> CGImage? {
        #if canImport(UIKit)
        guard let uiImage = UIImage(data: data),
              let cgImage = uiImage.cgImage else { return nil }
        return cgImage
        #elseif canImport(AppKit)
        guard let nsImage = NSImage(data: data),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return cgImage
        #endif
    }
}

