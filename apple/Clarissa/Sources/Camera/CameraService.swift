import Foundation
@preconcurrency import AVFoundation
import Vision
import CoreImage
import os.log
#if canImport(UIKit)
import UIKit
#endif

private let logger = Logger(subsystem: "dev.rye.Clarissa", category: "CameraService")

// MARK: - Camera Service
//
// Provides camera access for live image analysis.
// Captures photos for AI analysis using Foundation Models.
//
// Features:
// - Photo capture for image analysis
// - Camera permission handling
// - Front/back camera switching
// - Flash control

/// Camera capture result
public struct CapturedImage: Sendable {
    public let imageData: Data
    public let width: Int
    public let height: Int
    public let timestamp: Date
}

/// Detected document corners (normalized 0-1 coordinates)
public struct DocumentCorners: Sendable, Equatable {
    public let topLeft: CGPoint
    public let topRight: CGPoint
    public let bottomLeft: CGPoint
    public let bottomRight: CGPoint

    /// Check if corners are stable compared to previous detection
    public func isStable(comparedTo other: DocumentCorners, threshold: CGFloat = 0.02) -> Bool {
        let tl = hypot(topLeft.x - other.topLeft.x, topLeft.y - other.topLeft.y)
        let tr = hypot(topRight.x - other.topRight.x, topRight.y - other.topRight.y)
        let bl = hypot(bottomLeft.x - other.bottomLeft.x, bottomLeft.y - other.bottomLeft.y)
        let br = hypot(bottomRight.x - other.bottomRight.x, bottomRight.y - other.bottomRight.y)
        return tl < threshold && tr < threshold && bl < threshold && br < threshold
    }
}

/// Document scanning mode
public enum DocumentScanningMode: Sendable {
    case inactive
    case scanning
    case captured
}

/// Camera service errors
public enum CameraError: LocalizedError {
    case notAuthorized
    case deviceNotAvailable
    case captureSessionNotRunning
    case photoCaptureFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Camera access not authorized. Please enable in Settings."
        case .deviceNotAvailable:
            return "Camera device not available"
        case .captureSessionNotRunning:
            return "Camera session is not running"
        case .photoCaptureFailed(let reason):
            return "Photo capture failed: \(reason)"
        }
    }
}

/// Camera position
public enum CameraPosition: Sendable {
    case front
    case back

    var avPosition: AVCaptureDevice.Position {
        switch self {
        case .front: return .front
        case .back: return .back
        }
    }
}

/// Camera service for capturing images for AI analysis
@MainActor
public final class CameraService: NSObject, ObservableObject {

    // MARK: - Published Properties

    @Published public private(set) var isSessionRunning = false
    @Published public private(set) var currentPosition: CameraPosition = .back
    @Published public private(set) var isFlashEnabled = false
    @Published public private(set) var authorizationStatus: AVAuthorizationStatus = .notDetermined

    // Document scanning properties
    @Published public private(set) var documentScanningMode: DocumentScanningMode = .inactive
    @Published public private(set) var detectedCorners: DocumentCorners?
    @Published public private(set) var isDocumentStable = false

    // MARK: - Private Properties

    /// The capture session for camera access (internal for preview layer)
    let captureSession = AVCaptureSession()
    private var videoDeviceInput: AVCaptureDeviceInput?
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var photoContinuation: CheckedContinuation<CapturedImage, Error>?

    private let sessionQueue = DispatchQueue(label: "dev.rye.Clarissa.CameraSession")
    private let videoProcessingQueue = DispatchQueue(label: "dev.rye.Clarissa.VideoProcessing")

    // Document detection state
    private var previousCorners: DocumentCorners?
    private var stableFrameCount = 0
    private let stableFramesRequired = 15 // ~0.5 seconds at 30fps
    private nonisolated(unsafe) var isProcessingFrame = false
    private var documentScanCallback: ((CapturedImage) -> Void)?

    // MARK: - Initialization

    public override init() {
        super.init()
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    }

    // MARK: - Public API

    /// Request camera permission
    public func requestAuthorization() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .authorized:
            authorizationStatus = .authorized
            return true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            authorizationStatus = granted ? .authorized : .denied
            return granted
        default:
            authorizationStatus = status
            return false
        }
    }

    /// Configure and start the camera session
    public func startSession() async throws {
        guard authorizationStatus == .authorized else {
            throw CameraError.notAuthorized
        }

        // Configure on main actor
        try configureSession()

        // Start running on background queue
        let session = captureSession
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async {
                session.startRunning()
                continuation.resume()
            }
        }

        isSessionRunning = captureSession.isRunning
    }

    /// Stop the camera session
    public func stopSession() {
        let session = captureSession
        sessionQueue.async {
            session.stopRunning()
        }
        isSessionRunning = false
    }

    /// Capture a photo for analysis
    public func capturePhoto() async throws -> CapturedImage {
        guard captureSession.isRunning else {
            throw CameraError.captureSessionNotRunning
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.photoContinuation = continuation

            let settings = AVCapturePhotoSettings()
            settings.flashMode = isFlashEnabled ? .on : .off

            // Use HEIC for smaller file size if available
            if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                settings.photoQualityPrioritization = .balanced
            }

            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    /// Switch between front and back camera
    public func switchCamera() async throws {
        let newPosition: CameraPosition = currentPosition == .back ? .front : .back

        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        // Remove existing input
        if let currentInput = videoDeviceInput {
            captureSession.removeInput(currentInput)
        }

        // Add new input
        guard let device = Self.videoDevice(for: newPosition.avPosition) else {
            throw CameraError.deviceNotAvailable
        }

        let newInput = try AVCaptureDeviceInput(device: device)
        if captureSession.canAddInput(newInput) {
            captureSession.addInput(newInput)
            videoDeviceInput = newInput
            currentPosition = newPosition
        }
    }

    /// Toggle flash
    public func toggleFlash() {
        isFlashEnabled.toggle()
    }

    // MARK: - Document Scanning

    /// Start document scanning mode
    /// - Parameter onCapture: Callback when a stable document is auto-captured
    public func startDocumentScanning(onCapture: @escaping (CapturedImage) -> Void) {
        documentScanCallback = onCapture
        documentScanningMode = .scanning
        stableFrameCount = 0
        previousCorners = nil
        isDocumentStable = false

        // Add video output for frame processing if not already added
        if !captureSession.outputs.contains(videoOutput) {
            captureSession.beginConfiguration()
            if captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)
                videoOutput.setSampleBufferDelegate(self, queue: videoProcessingQueue)
                videoOutput.alwaysDiscardsLateVideoFrames = true
            }
            captureSession.commitConfiguration()
        }

        logger.info("Document scanning started")
    }

    /// Stop document scanning mode
    public func stopDocumentScanning() {
        documentScanningMode = .inactive
        documentScanCallback = nil
        detectedCorners = nil
        isDocumentStable = false
        stableFrameCount = 0
        previousCorners = nil

        logger.info("Document scanning stopped")
    }

    /// Manually trigger document capture (if corners are detected)
    public func captureDocument() async throws -> CapturedImage {
        guard detectedCorners != nil else {
            throw CameraError.photoCaptureFailed("No document detected")
        }

        documentScanningMode = .captured
        let image = try await capturePhoto()
        return image
    }

    // MARK: - Private Methods

    /// Configure the capture session
    private func configureSession() throws {
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        captureSession.sessionPreset = .photo

        // Add video input
        guard let videoDevice = Self.videoDevice(for: currentPosition.avPosition) else {
            throw CameraError.deviceNotAvailable
        }

        let videoInput = try AVCaptureDeviceInput(device: videoDevice)
        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
            videoDeviceInput = videoInput
        }

        // Add photo output
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
            photoOutput.isHighResolutionCaptureEnabled = true
            photoOutput.maxPhotoQualityPrioritization = .balanced
        }
    }

    private static func videoDevice(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        // Prefer wide angle camera
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) {
            return device
        }
        return AVCaptureDevice.default(for: .video)
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraService: AVCapturePhotoCaptureDelegate {

    nonisolated public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        // Extract data before entering Task to avoid data race
        let errorMessage = error?.localizedDescription
        let imageData = photo.fileDataRepresentation()
        let width = Int(photo.resolvedSettings.photoDimensions.width)
        let height = Int(photo.resolvedSettings.photoDimensions.height)

        Task { @MainActor in
            if let errorMessage = errorMessage {
                photoContinuation?.resume(throwing: CameraError.photoCaptureFailed(errorMessage))
                photoContinuation = nil
                return
            }

            guard let imageData = imageData else {
                photoContinuation?.resume(throwing: CameraError.photoCaptureFailed("No image data"))
                photoContinuation = nil
                return
            }

            let capturedImage = CapturedImage(
                imageData: imageData,
                width: width,
                height: height,
                timestamp: Date()
            )

            photoContinuation?.resume(returning: capturedImage)
            photoContinuation = nil
        }
    }
}

// MARK: - Camera Preview Layer Provider

extension CameraService {

    /// Get the preview layer for displaying camera feed
    public var previewLayer: AVCaptureVideoPreviewLayer {
        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        return layer
    }
}

// MARK: - Video Frame Processing for Document Detection

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {

    nonisolated public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Skip if not in scanning mode or already processing
        guard !isProcessingFrame else { return }
        isProcessingFrame = true
        defer { isProcessingFrame = false }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Perform document detection
        let request = VNDetectDocumentSegmentationRequest()

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return
        }

        guard let observation = request.results?.first else {
            Task { @MainActor in
                self.detectedCorners = nil
                self.isDocumentStable = false
                self.stableFrameCount = 0
            }
            return
        }

        let corners = DocumentCorners(
            topLeft: observation.topLeft,
            topRight: observation.topRight,
            bottomLeft: observation.bottomLeft,
            bottomRight: observation.bottomRight
        )

        Task { @MainActor in
            self.processDetectedCorners(corners)
        }
    }

    @MainActor
    private func processDetectedCorners(_ corners: DocumentCorners) {
        guard documentScanningMode == .scanning else { return }

        detectedCorners = corners

        // Check stability
        if let previous = previousCorners, corners.isStable(comparedTo: previous) {
            stableFrameCount += 1

            if stableFrameCount >= stableFramesRequired && !isDocumentStable {
                isDocumentStable = true
                logger.info("Document stable, auto-capturing...")

                // Auto-capture
                Task {
                    do {
                        let image = try await captureDocument()
                        documentScanCallback?(image)
                    } catch {
                        logger.error("Auto-capture failed: \(error.localizedDescription)")
                    }
                }
            }
        } else {
            stableFrameCount = 0
            isDocumentStable = false
        }

        previousCorners = corners
    }
}
