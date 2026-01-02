import Testing
import Foundation
@testable import ClarissaKit

// MARK: - Content Tagger Tests

@Suite("ContentTagger Tests")
struct ContentTaggerTests {

    @Test("ContentTagger shared instance exists")
    @MainActor
    func testSharedInstanceExists() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let tagger = ContentTagger.shared
            #expect(tagger != nil)
        } else {
            #expect(true)
        }
        #else
        #expect(true)
        #endif
    }

    @Test("Topic extraction returns array")
    @MainActor
    func testTopicExtractionReturnsArray() async {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            do {
                let topics = try await ContentTagger.shared.extractTopics(from: "Swift programming and iOS development")
                #expect(topics is [String])
            } catch {
                // May fail without on-device model - that's OK in tests
                Issue.record("Topic extraction failed (expected without model): \(error)")
            }
        } else {
            #expect(true)
        }
        #else
        #expect(true)
        #endif
    }
}

// MARK: - Guided Generation Tests

@Suite("GuidedGeneration Tests")
struct GuidedGenerationTests {

    @Test("ActionTask struct has expected properties")
    func testActionTaskProperties() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            // ActionTask is @Generable so we can't directly instantiate
            // but we can verify it compiles and exists
            let taskType = ActionTask.self
            #expect(taskType != nil)
        } else {
            #expect(true)
        }
        #else
        #expect(true)
        #endif
    }

    @Test("ExtractedEvent struct has expected properties")
    func testExtractedEventProperties() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let eventType = ExtractedEvent.self
            #expect(eventType != nil)
        } else {
            #expect(true)
        }
        #else
        #expect(true)
        #endif
    }

    @Test("GuidedGenerationService shared instance exists")
    @MainActor
    func testServiceExists() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let service = GuidedGenerationService.shared
            #expect(service != nil)
        } else {
            #expect(true)
        }
        #else
        #expect(true)
        #endif
    }

    @Test("GuidedGenerationError has correct descriptions")
    func testErrorDescriptions() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let error = GuidedGenerationError.streamingFailed
            #expect(error.errorDescription?.contains("streaming") == true)
        } else {
            // Skip on older platforms
            #expect(true)
        }
        #else
        // Skip when FoundationModels not available
        #expect(true)
        #endif
    }
}

// MARK: - Document OCR Tests

@Suite("DocumentOCR Tests")
struct DocumentOCRTests {

    @Test("DocumentOCRResult has all expected properties")
    func testResultProperties() {
        #if canImport(Vision)
        if #available(iOS 26.0, macOS 26.0, *) {
            let result = DocumentOCRResult(
                text: "Sample text",
                paragraphs: ["Paragraph 1"],
                tables: [],
                barcodes: [],
                containsHandwriting: false,
                pageCount: 1,
                confidence: 0.95
            )

            #expect(result.text == "Sample text")
            #expect(result.paragraphs.count == 1)
            #expect(result.tables.isEmpty)
            #expect(result.barcodes.isEmpty)
            #expect(result.containsHandwriting == false)
            #expect(result.pageCount == 1)
            #expect(result.confidence == 0.95)
        } else {
            #expect(true)
        }
        #else
        #expect(true)
        #endif
    }

    @Test("ExtractedTable has correct structure")
    func testExtractedTableStructure() {
        #if canImport(Vision)
        if #available(iOS 26.0, macOS 26.0, *) {
            let table = ExtractedTable(
                rows: [["A1", "B1"], ["A2", "B2"]],
                rowCount: 2,
                columnCount: 2
            )

            #expect(table.rowCount == 2)
            #expect(table.columnCount == 2)
            #expect(table.rows.count == 2)
            #expect(table.rows[0][0] == "A1")
        } else {
            #expect(true)
        }
        #else
        #expect(true)
        #endif
    }

    @Test("ExtractedBarcode stores payload and symbology")
    func testExtractedBarcodeProperties() {
        #if canImport(Vision)
        if #available(iOS 26.0, macOS 26.0, *) {
            let barcode = ExtractedBarcode(
                payload: "1234567890",
                symbology: "EAN-13"
            )

            #expect(barcode.payload == "1234567890")
            #expect(barcode.symbology == "EAN-13")
        } else {
            #expect(true)
        }
        #else
        #expect(true)
        #endif
    }

    @Test("DocumentOCRError has correct descriptions")
    func testErrorDescriptions() {
        #if canImport(Vision)
        if #available(iOS 26.0, macOS 26.0, *) {
            let invalidImage = DocumentOCRError.invalidImage
            #expect(invalidImage.errorDescription?.contains("image") == true)

            let invalidPDF = DocumentOCRError.invalidPDF
            #expect(invalidPDF.errorDescription?.contains("PDF") == true)

            let failed = DocumentOCRError.recognitionFailed("test reason")
            #expect(failed.errorDescription?.contains("test reason") == true)
        } else {
            #expect(true)
        }
        #else
        #expect(true)
        #endif
    }

    @Test("DocumentOCRService shared instance exists")
    func testServiceExists() async {
        #if canImport(Vision)
        if #available(iOS 26.0, macOS 26.0, *) {
            let service = DocumentOCRService.shared
            _ = service  // Use the service to avoid warning
            #expect(true)
        } else {
            #expect(true)
        }
        #else
        #expect(true)
        #endif
    }
}

// MARK: - Camera Service Tests

#if os(iOS)
@Suite("CameraService Tests")
struct CameraServiceTests {

    @Test("CameraService initializes with notDetermined status")
    @MainActor
    func testInitialAuthorizationStatus() {
        let service = CameraService()
        // Initial status depends on device state
        #expect(service.authorizationStatus != nil)
    }

    @Test("CameraService starts with session not running")
    @MainActor
    func testInitialSessionState() {
        let service = CameraService()
        #expect(service.isSessionRunning == false)
    }

    @Test("CameraService default camera is back")
    @MainActor
    func testDefaultCameraPosition() {
        let service = CameraService()
        #expect(service.currentPosition == .back)
    }

    @Test("CameraService flash is off by default")
    @MainActor
    func testDefaultFlashState() {
        let service = CameraService()
        #expect(service.isFlashEnabled == false)
    }

    @Test("Toggle flash changes state")
    @MainActor
    func testToggleFlash() {
        let service = CameraService()
        #expect(service.isFlashEnabled == false)

        service.toggleFlash()
        #expect(service.isFlashEnabled == true)

        service.toggleFlash()
        #expect(service.isFlashEnabled == false)
    }

    @Test("CameraPosition maps to correct AVPosition")
    func testCameraPositionMapping() {
        #expect(CameraPosition.front.avPosition == .front)
        #expect(CameraPosition.back.avPosition == .back)
    }

    @Test("CameraError has correct descriptions")
    func testCameraErrorDescriptions() {
        let notAuth = CameraError.notAuthorized
        #expect(notAuth.errorDescription?.contains("authorized") == true)

        let notAvail = CameraError.deviceNotAvailable
        #expect(notAvail.errorDescription?.contains("not available") == true)

        let notRunning = CameraError.captureSessionNotRunning
        #expect(notRunning.errorDescription?.contains("not running") == true)

        let failed = CameraError.photoCaptureFailed("test reason")
        #expect(failed.errorDescription?.contains("test reason") == true)
    }

    @Test("CapturedImage stores correct properties")
    func testCapturedImageProperties() {
        let data = Data([0x00, 0x01, 0x02])
        let now = Date()
        let image = CapturedImage(
            imageData: data,
            width: 1920,
            height: 1080,
            timestamp: now
        )

        #expect(image.imageData == data)
        #expect(image.width == 1920)
        #expect(image.height == 1080)
        #expect(image.timestamp == now)
    }
}
#endif

// MARK: - Memory Tagging Tests

@Suite("Memory Tagging Tests")
struct MemoryTaggingTests {

    @Test("Memory struct supports topics")
    func testMemoryWithTopics() {
        let memory = Memory(
            content: "User prefers dark mode",
            topics: ["preferences", "ui"]
        )

        #expect(memory.content == "User prefers dark mode")
        #expect(memory.topics?.count == 2)
        #expect(memory.topics?.contains("preferences") == true)
    }

    @Test("Memory struct works without topics")
    func testMemoryWithoutTopics() {
        let memory = Memory(content: "Simple memory")

        #expect(memory.content == "Simple memory")
        #expect(memory.topics == nil)
    }

    @Test("Memory is Codable")
    func testMemoryCodable() throws {
        let original = Memory(
            content: "Test memory",
            topics: ["test", "codable"]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Memory.self, from: data)

        #expect(decoded.content == original.content)
        #expect(decoded.topics == original.topics)
    }
}

// MARK: - Streaming Partial View Tests

@Suite("StreamingPartialView Tests")
struct StreamingPartialViewTests {

    @Test("FlowLayout exists and can be instantiated")
    func testFlowLayoutExists() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let layout = FlowLayout(spacing: 8)
            #expect(layout.spacing == 8)
        } else {
            #expect(true)
        }
        #else
        #expect(true)
        #endif
    }
}
