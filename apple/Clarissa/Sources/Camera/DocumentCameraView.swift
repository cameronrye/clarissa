import SwiftUI
import AVFoundation

#if os(iOS)

// MARK: - Document Camera View
//
// SwiftUI view for document scanning with real-time corner detection overlay.
// Automatically captures when document is stable for ~0.5 seconds.

/// Document scanning result
public struct ScannedDocument: Sendable {
    public let imageData: Data
    public let corners: DocumentCorners
    public let timestamp: Date
}

/// Document camera view with corner overlay and auto-capture
@available(iOS 26.0, *)
public struct DocumentCameraView: View {
    @StateObject private var cameraService = CameraService()
    @State private var errorMessage: String?
    @State private var showStabilityIndicator = false

    let onDocumentScanned: (ScannedDocument) -> Void
    let onDismiss: () -> Void

    public init(
        onDocumentScanned: @escaping (ScannedDocument) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.onDocumentScanned = onDocumentScanned
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            // Camera preview
            if cameraService.isSessionRunning {
                CameraPreviewView(cameraService: cameraService)
                    .ignoresSafeArea()

                // Document corner overlay
                if let corners = cameraService.detectedCorners {
                    DocumentCornerOverlay(corners: corners, isStable: cameraService.isDocumentStable)
                }
            } else {
                Color.black
                    .ignoresSafeArea()
                    .overlay {
                        if cameraService.authorizationStatus == .denied {
                            permissionDeniedView
                        } else {
                            ProgressView("Starting camera...")
                                .tint(.white)
                        }
                    }
            }

            // Controls overlay
            VStack {
                topBar
                Spacer()
                instructionText
                bottomControls
            }

            // Stability indicator
            if cameraService.isDocumentStable {
                stabilityIndicator
            }
        }
        .task { await setupCamera() }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var topBar: some View {
        HStack {
            Button { onDismiss() } label: {
                Image(systemName: "xmark")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .padding()
            }
            Spacer()
            if cameraService.documentScanningMode == .scanning {
                Text("Scanning")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.green.opacity(0.8), in: Capsule())
                    .padding()
            }
        }
        .background(.ultraThinMaterial.opacity(0.5))
    }

    private var instructionText: some View {
        Text(cameraService.detectedCorners != nil
            ? (cameraService.isDocumentStable ? "Hold steady..." : "Align document")
            : "Position document in view")
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, 20)
    }

    private var bottomControls: some View {
        HStack(spacing: 40) {
            // Manual capture button
            Button {
                Task { await manualCapture() }
            } label: {
                ZStack {
                    Circle()
                        .stroke(.white, lineWidth: 4)
                        .frame(width: 70, height: 70)
                    Circle()
                        .fill(.white)
                        .frame(width: 58, height: 58)
                }
            }
            .disabled(cameraService.detectedCorners == nil)
            .opacity(cameraService.detectedCorners == nil ? 0.5 : 1)
        }
        .padding(.bottom, 40)
        .background(.ultraThinMaterial.opacity(0.5))
    }

    private var stabilityIndicator: some View {
        VStack {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.green)
            Text("Capturing...")
                .font(.headline)
                .foregroundStyle(.white)
        }
        .padding(30)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Camera Access Required")
                .font(.headline)
                .foregroundStyle(.white)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func setupCamera() async {
        let authorized = await cameraService.requestAuthorization()
        if authorized {
            do {
                try await cameraService.startSession()
                cameraService.startDocumentScanning { captured in
                    handleCapture(captured)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func handleCapture(_ captured: CapturedImage) {
        guard let corners = cameraService.detectedCorners else { return }
        cameraService.stopDocumentScanning()

        let document = ScannedDocument(
            imageData: captured.imageData,
            corners: corners,
            timestamp: captured.timestamp
        )
        onDocumentScanned(document)
    }

    private func manualCapture() async {
        do {
            let captured = try await cameraService.captureDocument()
            handleCapture(captured)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Document Corner Overlay

/// Draws the detected document corners as a polygon overlay
@available(iOS 26.0, *)
struct DocumentCornerOverlay: View {
    let corners: DocumentCorners
    let isStable: Bool

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let size = geometry.size

                // Convert normalized coordinates to view coordinates
                // Vision uses bottom-left origin, SwiftUI uses top-left
                let tl = CGPoint(x: corners.topLeft.x * size.width,
                                 y: (1 - corners.topLeft.y) * size.height)
                let tr = CGPoint(x: corners.topRight.x * size.width,
                                 y: (1 - corners.topRight.y) * size.height)
                let br = CGPoint(x: corners.bottomRight.x * size.width,
                                 y: (1 - corners.bottomRight.y) * size.height)
                let bl = CGPoint(x: corners.bottomLeft.x * size.width,
                                 y: (1 - corners.bottomLeft.y) * size.height)

                path.move(to: tl)
                path.addLine(to: tr)
                path.addLine(to: br)
                path.addLine(to: bl)
                path.closeSubpath()
            }
            .stroke(isStable ? Color.green : Color.yellow, lineWidth: 3)
            .animation(.easeInOut(duration: 0.2), value: isStable)
        }
    }
}

#endif
