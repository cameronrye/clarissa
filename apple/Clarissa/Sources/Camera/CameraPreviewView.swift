import SwiftUI
import AVFoundation

#if os(iOS)

// MARK: - Camera Preview View
//
// SwiftUI view for displaying camera preview with capture controls.
// Integrates with CameraService for photo capture and AI analysis.

/// SwiftUI wrapper for AVCaptureVideoPreviewLayer
struct CameraPreviewView: UIViewRepresentable {
    let cameraService: CameraService

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.previewLayer.session = cameraService.captureSession
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        // Preview layer updates automatically with session
    }
}

/// UIView subclass that hosts the camera preview layer
class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
        previewLayer.videoGravity = .resizeAspectFill
    }
}

// MARK: - Camera Capture View

/// Full camera capture interface with controls
@available(iOS 26.0, *)
struct CameraCaptureView: View {
    @StateObject private var cameraService = CameraService()
    @State private var capturedImage: CapturedImage?
    @State private var isAnalyzing = false
    @State private var analysisResult: String?
    @State private var errorMessage: String?

    let onImageCaptured: (CapturedImage) -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Camera preview
            if cameraService.isSessionRunning {
                CameraPreviewView(cameraService: cameraService)
                    .ignoresSafeArea()
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
                // Top bar
                HStack {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .padding()
                    }

                    Spacer()

                    Button {
                        cameraService.toggleFlash()
                    } label: {
                        Image(systemName: cameraService.isFlashEnabled ? "bolt.fill" : "bolt.slash")
                            .font(.title2)
                            .foregroundStyle(cameraService.isFlashEnabled ? .yellow : .white)
                            .padding()
                    }
                }
                .background(.ultraThinMaterial.opacity(0.5))

                Spacer()

                // Bottom controls
                HStack(spacing: 40) {
                    // Switch camera
                    Button {
                        Task {
                            try? await cameraService.switchCamera()
                        }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.title)
                            .foregroundStyle(.white)
                    }

                    // Capture button
                    Button {
                        Task { await captureAndAnalyze() }
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
                    .disabled(isAnalyzing)

                    // Placeholder for symmetry
                    Color.clear
                        .frame(width: 44, height: 44)
                }
                .padding(.bottom, 40)
                .background(.ultraThinMaterial.opacity(0.5))
            }

            // Analysis overlay
            if isAnalyzing {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .overlay {
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)
                            Text("Analyzing image...")
                                .foregroundStyle(.white)
                        }
                    }
            }
        }
        .task {
            await setupCamera()
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Camera Access Required")
                .font(.headline)
                .foregroundStyle(.white)

            Text("Please enable camera access in Settings to use this feature.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

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
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func captureAndAnalyze() async {
        isAnalyzing = true
        defer { isAnalyzing = false }

        do {
            let image = try await cameraService.capturePhoto()
            capturedImage = image
            onImageCaptured(image)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#endif

