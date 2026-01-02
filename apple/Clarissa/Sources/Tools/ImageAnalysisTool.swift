import Foundation
import Vision
import PDFKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Tool for analyzing images and PDFs using Apple's Vision and PDFKit frameworks.
/// NOTE: For user-attached images, pre-processing happens BEFORE the LLM call
/// via ImagePreProcessor. This tool is for targeted follow-up operations on
/// files referenced by URL (e.g., "get face coordinates" or "extract page 5").
/// Only file:// URLs are supported to stay within context limits.
final class ImageAnalysisTool: ClarissaTool, @unchecked Sendable {
    let name = "image_analysis"
    let description = "Perform targeted analysis on images or PDFs via file URL. Actions: 'ocr' (text), 'handwriting' (handwritten text), 'classify' (objects), 'detect_faces', 'detect_document', 'compare' (multi-image), 'pdf_extract_text', 'pdf_ocr', 'pdf_page_count'. Only file:// URLs supported."
    let priority = ToolPriority.extended

    /// Maximum characters to return from PDF text extraction
    private let maxPDFTextLength = 15000

    /// Maximum pages to OCR from a PDF
    private let maxPDFPagesToOCR = 10

    var parametersSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "action": [
                    "type": "string",
                    "enum": ["ocr", "handwriting", "classify", "detect_faces", "detect_document", "scan_document", "compare", "pdf_extract_text", "pdf_ocr", "pdf_page_count"],
                    "description": "Analysis type: 'ocr' for printed text, 'handwriting' for handwritten text, 'classify' for objects, 'detect_faces' for faces, 'detect_document' for boundaries, 'scan_document' for document OCR with perspective correction, 'compare' for multi-image comparison, 'pdf_extract_text' for searchable PDFs, 'pdf_ocr' for scanned PDFs, 'pdf_page_count' for page count"
                ],
                "imageURL": [
                    "type": "string",
                    "description": "File URL to the image (file:// scheme only)"
                ],
                "imageURLs": [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": "Array of file URLs for 'compare' action (2-5 images)"
                ],
                "pdfURL": [
                    "type": "string",
                    "description": "File URL to the PDF (file:// scheme only)"
                ],
                "pageRange": [
                    "type": "string",
                    "description": "Page range for PDF operations, e.g., '1-5' or '1,3,5' (optional, defaults to all pages)"
                ],
                "comparisonPrompt": [
                    "type": "string",
                    "description": "Optional prompt for 'compare' action (e.g., 'What changed between these images?')"
                ]
            ],
            "required": ["action"]
        ]
    }

    func execute(arguments: String) async throws -> String {
        guard let data = arguments.data(using: .utf8),
              let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = args["action"] as? String else {
            throw ToolError.invalidArguments("Missing required 'action' parameter")
        }

        let pageRange = args["pageRange"] as? String

        // Handle PDF actions (file URLs only)
        if action.hasPrefix("pdf_") {
            guard let urlString = args["pdfURL"] as? String,
                  let url = URL(string: urlString) else {
                throw ToolError.invalidArguments("PDF actions require 'pdfURL' (file:// URL)")
            }
            let pdfDocument = try pdfFromURL(url)

            switch action {
            case "pdf_extract_text":
                return try extractTextFromPDF(pdfDocument, pageRange: pageRange)
            case "pdf_ocr":
                return try await ocrPDF(pdfDocument, pageRange: pageRange)
            case "pdf_page_count":
                return jsonResponse(["pageCount": pdfDocument.pageCount])
            default:
                throw ToolError.invalidArguments("Unknown PDF action: \(action)")
            }
        }

        // Handle multi-image compare action
        if action == "compare" {
            guard let urlStrings = args["imageURLs"] as? [String], urlStrings.count >= 2 else {
                throw ToolError.invalidArguments("'compare' action requires 'imageURLs' array with 2-5 images")
            }
            let comparisonPrompt = args["comparisonPrompt"] as? String
            return try await compareImages(urlStrings: urlStrings, prompt: comparisonPrompt)
        }

        // Handle image actions (file URLs only)
        guard let urlString = args["imageURL"] as? String,
              let url = URL(string: urlString) else {
            throw ToolError.invalidArguments("Image actions require 'imageURL' (file:// URL)")
        }

        switch action {
        case "ocr":
            let cgImage = try imageFromURL(url)
            return try await performOCR(on: cgImage)
        case "handwriting":
            let imageData = try dataFromURL(url)
            return try await performHandwritingRecognition(on: imageData)
        case "classify":
            let cgImage = try imageFromURL(url)
            return try await performClassification(on: cgImage)
        case "detect_faces":
            let cgImage = try imageFromURL(url)
            return try await detectFaces(in: cgImage)
        case "detect_document":
            let cgImage = try imageFromURL(url)
            return try await detectDocument(in: cgImage)
        case "scan_document":
            let imageData = try dataFromURL(url)
            return try await scanDocument(from: imageData)
        default:
            throw ToolError.invalidArguments("Unknown action: \(action)")
        }
    }

    // MARK: - Image Loading

    private func imageFromURL(_ url: URL) throws -> CGImage {
        guard url.isFileURL else {
            throw ToolError.invalidArguments("Only file:// URLs are supported")
        }

        let imageData = try Data(contentsOf: url)
        return try cgImageFromData(imageData)
    }

    private func dataFromURL(_ url: URL) throws -> Data {
        guard url.isFileURL else {
            throw ToolError.invalidArguments("Only file:// URLs are supported")
        }
        return try Data(contentsOf: url)
    }

    private func cgImageFromData(_ data: Data) throws -> CGImage {
        #if canImport(UIKit)
        guard let uiImage = UIImage(data: data),
              let cgImage = uiImage.cgImage else {
            throw ToolError.executionFailed("Failed to decode image data")
        }
        return cgImage
        #elseif canImport(AppKit)
        guard let nsImage = NSImage(data: data),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ToolError.executionFailed("Failed to decode image data")
        }
        return cgImage
        #endif
    }

    // MARK: - Vision Analysis Methods

    private func performOCR(on image: CGImage) async throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        guard let observations = request.results else {
            return jsonResponse(["text": "", "lineCount": 0])
        }

        let recognizedText = observations.compactMap { observation in
            observation.topCandidates(1).first?.string
        }

        return jsonResponse([
            "text": recognizedText.joined(separator: "\n"),
            "lineCount": recognizedText.count
        ])
    }

    private func performClassification(on image: CGImage) async throws -> String {
        let request = VNClassifyImageRequest()

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        guard let observations = request.results else {
            return jsonResponse(["classifications": []])
        }

        // Return top 5 classifications with confidence > 10%
        let topResults = observations
            .filter { $0.confidence > 0.1 }
            .prefix(5)
            .map { ["label": $0.identifier, "confidence": Double($0.confidence)] }

        return jsonResponse(["classifications": Array(topResults)])
    }

    private func detectFaces(in image: CGImage) async throws -> String {
        let request = VNDetectFaceRectanglesRequest()

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        guard let observations = request.results else {
            return jsonResponse(["faceCount": 0, "faces": []])
        }

        let faces = observations.map { observation -> [String: Any] in
            let box = observation.boundingBox
            return [
                "x": box.origin.x,
                "y": box.origin.y,
                "width": box.width,
                "height": box.height,
                "confidence": Double(observation.confidence)
            ]
        }

        return jsonResponse([
            "faceCount": observations.count,
            "faces": faces
        ])
    }

    private func detectDocument(in image: CGImage) async throws -> String {
        let request = VNDetectDocumentSegmentationRequest()

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        guard let observations = request.results, let document = observations.first else {
            return jsonResponse(["documentDetected": false])
        }

        // Get the four corners of the detected document
        let corners: [[String: CGFloat]] = [
            ["x": document.topLeft.x, "y": document.topLeft.y],
            ["x": document.topRight.x, "y": document.topRight.y],
            ["x": document.bottomRight.x, "y": document.bottomRight.y],
            ["x": document.bottomLeft.x, "y": document.bottomLeft.y]
        ]

        return jsonResponse([
            "documentDetected": true,
            "corners": corners,
            "confidence": Double(document.confidence)
        ])
    }

    private func performHandwritingRecognition(on imageData: Data) async throws -> String {
        if #available(iOS 26.0, macOS 26.0, *) {
            let result = try await DocumentOCRService.shared.recognizeHandwriting(from: imageData)
            return jsonResponse([
                "text": result.text,
                "lineCount": result.lines.count,
                "confidence": Double(result.confidence),
                "isHandwritten": result.isHandwritten,
                "lines": result.lines.map { ["text": $0.text, "confidence": Double($0.confidence)] }
            ])
        } else {
            // Fall back to standard OCR for older versions
            let cgImage = try cgImageFromData(imageData)
            return try await performOCR(on: cgImage)
        }
    }

    private func scanDocument(from imageData: Data) async throws -> String {
        if #available(iOS 26.0, macOS 26.0, *) {
            let result = try await DocumentOCRService.shared.scanDocument(from: imageData)
            return jsonResponse([
                "text": result.text,
                "paragraphCount": result.paragraphs.count,
                "confidence": Double(result.confidence),
                "containsHandwriting": result.containsHandwriting,
                "perspectiveCorrected": true
            ])
        } else {
            // Fall back to standard OCR without perspective correction
            let cgImage = try cgImageFromData(imageData)
            return try await performOCR(on: cgImage)
        }
    }

    private func compareImages(urlStrings: [String], prompt: String?) async throws -> String {
        // Limit to 5 images maximum
        let limitedURLs = Array(urlStrings.prefix(5))

        var imageAnalyses: [[String: Any]] = []

        for (index, urlString) in limitedURLs.enumerated() {
            guard let url = URL(string: urlString) else {
                throw ToolError.invalidArguments("Invalid URL at index \(index): \(urlString)")
            }

            let cgImage = try imageFromURL(url)

            // Get basic analysis for each image
            let ocrResult = try await performOCRInternal(on: cgImage)
            let classificationResult = try await performClassificationInternal(on: cgImage)
            let faceResult = try await detectFacesInternal(in: cgImage)

            var analysis: [String: Any] = [
                "imageIndex": index + 1,
                "url": urlString
            ]

            if !ocrResult.isEmpty {
                analysis["text"] = ocrResult
            }
            if !classificationResult.isEmpty {
                analysis["classifications"] = classificationResult
            }
            analysis["faceCount"] = faceResult

            imageAnalyses.append(analysis)
        }

        // Build comparison summary
        var response: [String: Any] = [
            "imageCount": limitedURLs.count,
            "images": imageAnalyses
        ]

        if let prompt = prompt {
            response["comparisonPrompt"] = prompt
        }

        // Add comparison hints
        if imageAnalyses.count >= 2 {
            var hints: [String] = []

            // Compare text content
            let texts = imageAnalyses.compactMap { $0["text"] as? String }
            if texts.count >= 2 {
                let allSame = texts.dropFirst().allSatisfy { $0 == texts.first }
                hints.append(allSame ? "Text content appears identical" : "Text content differs between images")
            }

            // Compare face counts
            let faceCounts = imageAnalyses.compactMap { $0["faceCount"] as? Int }
            if faceCounts.count >= 2 && faceCounts.contains(where: { $0 > 0 }) {
                let totalFaces = faceCounts.reduce(0, +)
                hints.append("Total faces across images: \(totalFaces)")
            }

            if !hints.isEmpty {
                response["comparisonHints"] = hints
            }
        }

        return jsonResponse(response)
    }

    // Internal versions that return raw values for comparison
    private func performOCRInternal(on image: CGImage) async throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        return request.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n") ?? ""
    }

    private func performClassificationInternal(on image: CGImage) async throws -> [String] {
        let request = VNClassifyImageRequest()

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        return request.results?
            .filter { $0.confidence > 0.1 }
            .prefix(3)
            .map { $0.identifier } ?? []
    }

    private func detectFacesInternal(in image: CGImage) async throws -> Int {
        let request = VNDetectFaceRectanglesRequest()

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        return request.results?.count ?? 0
    }

    // MARK: - PDF Loading

    private func pdfFromURL(_ url: URL) throws -> PDFDocument {
        guard url.isFileURL else {
            throw ToolError.invalidArguments("Only file:// URLs are supported for PDFs")
        }

        guard let document = PDFDocument(url: url) else {
            throw ToolError.executionFailed("Failed to load PDF from URL")
        }
        return document
    }

    // MARK: - PDF Analysis Methods

    private func extractTextFromPDF(_ document: PDFDocument, pageRange: String?) throws -> String {
        let pages = try parsePageRange(pageRange, totalPages: document.pageCount)
        var allText = ""
        var pageTexts: [[String: Any]] = []

        for pageIndex in pages {
            guard let page = document.page(at: pageIndex) else { continue }
            let pageText = page.string ?? ""

            if !pageText.isEmpty {
                pageTexts.append([
                    "page": pageIndex + 1,
                    "text": String(pageText.prefix(maxPDFTextLength / pages.count))
                ])
                allText += pageText + "\n\n"
            }
        }

        // Truncate if too long
        let truncated = allText.count > maxPDFTextLength
        let finalText = truncated ? String(allText.prefix(maxPDFTextLength)) + "..." : allText

        return jsonResponse([
            "text": finalText.trimmingCharacters(in: .whitespacesAndNewlines),
            "pageCount": document.pageCount,
            "pagesExtracted": pages.count,
            "truncated": truncated,
            "characterCount": min(allText.count, maxPDFTextLength)
        ])
    }

    private func ocrPDF(_ document: PDFDocument, pageRange: String?) async throws -> String {
        let pages = try parsePageRange(pageRange, totalPages: document.pageCount)
        let pagesToProcess = Array(pages.prefix(maxPDFPagesToOCR))
        var pageResults: [[String: Any]] = []
        var allText = ""

        for pageIndex in pagesToProcess {
            guard let page = document.page(at: pageIndex) else { continue }

            // Render page to image
            guard let cgImage = renderPageToImage(page) else { continue }

            // Perform OCR on the page image
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform([request])

            let pageText = request.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n") ?? ""

            if !pageText.isEmpty {
                pageResults.append([
                    "page": pageIndex + 1,
                    "text": String(pageText.prefix(maxPDFTextLength / pagesToProcess.count))
                ])
                allText += "--- Page \(pageIndex + 1) ---\n\(pageText)\n\n"
            }
        }

        let truncated = allText.count > maxPDFTextLength
        let finalText = truncated ? String(allText.prefix(maxPDFTextLength)) + "..." : allText

        return jsonResponse([
            "text": finalText.trimmingCharacters(in: .whitespacesAndNewlines),
            "pageCount": document.pageCount,
            "pagesProcessed": pagesToProcess.count,
            "truncated": truncated,
            "skippedPages": pages.count > maxPDFPagesToOCR ? pages.count - maxPDFPagesToOCR : 0
        ])
    }

    private func renderPageToImage(_ page: PDFPage) -> CGImage? {
        let pageRect = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0  // 2x for better OCR quality

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

    private func parsePageRange(_ range: String?, totalPages: Int) throws -> [Int] {
        guard let range = range, !range.isEmpty else {
            // Default to all pages
            return Array(0..<totalPages)
        }

        var pages: Set<Int> = []

        // Handle comma-separated values and ranges
        let parts = range.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        for part in parts {
            if part.contains("-") {
                // Range like "1-5"
                let rangeParts = part.split(separator: "-").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                if rangeParts.count == 2 {
                    let start = max(1, rangeParts[0]) - 1  // Convert to 0-indexed
                    let end = min(totalPages, rangeParts[1]) - 1
                    for i in start...end {
                        pages.insert(i)
                    }
                }
            } else if let pageNum = Int(part) {
                // Single page number
                let index = pageNum - 1  // Convert to 0-indexed
                if index >= 0 && index < totalPages {
                    pages.insert(index)
                }
            }
        }

        if pages.isEmpty {
            throw ToolError.invalidArguments("Invalid page range: \(range)")
        }

        return pages.sorted()
    }

    // MARK: - Helpers

    private func jsonResponse(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: []),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}

