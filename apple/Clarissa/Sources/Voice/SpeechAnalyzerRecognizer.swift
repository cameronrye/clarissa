import Foundation
@preconcurrency import Speech
@preconcurrency import AVFoundation

/// Handles speech-to-text using Apple's new SpeechAnalyzer API (iOS 26+)
/// This provides significantly better accuracy and performance than the legacy SFSpeechRecognizer
/// Powers transcription in Notes and Voice Memos in iOS 26
@available(iOS 26.0, macOS 26.0, *)
@MainActor
final class SpeechAnalyzerRecognizer: ObservableObject {
    @Published var transcript: String = ""
    @Published var isRecording: Bool = false
    @Published var isAvailable: Bool = true
    @Published var error: String?

    private var speechAnalyzer: SpeechAnalyzer?
    private var speechTranscriber: SpeechTranscriber?
    private var analysisTask: Task<Void, Never>?
    private var analyzerFormat: AVAudioFormat?

    // Audio capture - use a helper class to handle audio on a dedicated queue
    // This avoids @MainActor isolation issues with the audio tap callback
    private let audioHandler = SpeechAnalyzerAudioHandler()

    /// Whether audio session is managed externally (e.g., by VoiceManager in voice mode)
    var useExternalAudioSession: Bool = false

    private let locale: Locale

    init(locale: Locale = Locale(identifier: "en-US")) {
        self.locale = locale
        // SpeechAnalyzer is always available on iOS 26+ devices with Apple Intelligence
        isAvailable = true
    }

    /// Request authorization for speech recognition
    func requestAuthorization() async -> Bool {
        // Use non-isolated helper to avoid dispatch queue assertion failures
        // when the TCC callback runs on a background queue
        let status = await requestSpeechAnalyzerAuthorizationStatus()

        switch status {
        case .authorized:
            isAvailable = true
            return true
        case .denied, .restricted, .notDetermined:
            isAvailable = false
            error = "Speech recognition not authorized"
            return false
        @unknown default:
            isAvailable = false
            return false
        }
    }

    /// Start recording and transcribing speech using SpeechAnalyzer
    func startRecording() async throws {
        // Cancel any existing analysis
        stopRecordingInternal()

        // Create SpeechTranscriber module with volatile results for live feedback
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        self.speechTranscriber = transcriber

        // Create SpeechAnalyzer with the transcriber module
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.speechAnalyzer = analyzer

        // Get the best audio format for the transcriber
        self.analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])

        // Create async stream for audio input
        let (inputSequence, continuation) = AsyncStream<AnalyzerInput>.makeStream()

        isRecording = true
        transcript = ""
        error = nil

        // Start audio capture on dedicated queue to avoid @MainActor isolation crash
        // The audio tap callback runs on a real-time audio thread
        let format = self.analyzerFormat
        try await audioHandler.start(
            skipSessionConfig: useExternalAudioSession,
            targetFormat: format
        ) { buffer in
            let input = AnalyzerInput(buffer: buffer)
            continuation.yield(input)
        }

        // Start analysis task
        analysisTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                // Start the analyzer with the input sequence
                try await analyzer.start(inputSequence: inputSequence)

                // Stream transcription results - accumulate finalized text
                var finalizedTranscript = ""
                for try await result in transcriber.results {
                    if Task.isCancelled { break }
                    if result.isFinal {
                        finalizedTranscript += String(result.text.characters)
                        self.transcript = finalizedTranscript
                    } else {
                        // Show volatile (in-progress) results appended to finalized
                        self.transcript = finalizedTranscript + String(result.text.characters)
                    }
                }
            } catch {
                if !Task.isCancelled {
                    self.error = error.localizedDescription
                }
            }

            // Signal end of audio input
            continuation.finish()
            self.stopRecordingInternal()
        }
    }

    /// Stop recording and finalize transcription
    private func stopRecordingInternal() {
        analysisTask?.cancel()
        analysisTask = nil

        // Stop audio capture on dedicated queue
        audioHandler.stopSync(skipSessionDeactivation: useExternalAudioSession)

        speechAnalyzer = nil
        speechTranscriber = nil
        analyzerFormat = nil
        isRecording = false
    }

    /// Stop recording and finalize transcription
    func stopRecording() {
        // Finalize the analyzer to ensure volatile results become final
        Task {
            try? await speechAnalyzer?.finalizeAndFinishThroughEndOfInput()
        }
        stopRecordingInternal()
    }

    /// Toggle recording state
    func toggleRecording() async {
        if isRecording {
            stopRecording()
        } else {
            do {
                try await startRecording()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

// MARK: - Audio Handler

/// Handles AVAudioEngine operations on a dedicated queue to avoid @MainActor isolation crashes
/// The audio tap callback runs on a real-time audio thread, which conflicts with Swift 6 strict concurrency
@available(iOS 26.0, macOS 26.0, *)
private final class SpeechAnalyzerAudioHandler: @unchecked Sendable {
    private let audioEngine = AVAudioEngine()
    private let queue = DispatchQueue(label: "com.clarissa.speechanalyzer.audio", qos: .userInitiated)
    private var currentBufferHandler: (@Sendable (AVAudioPCMBuffer) -> Void)?

    /// Start audio capture
    /// - Parameters:
    ///   - skipSessionConfig: If true, skips audio session configuration (use when VoiceManager manages the session)
    ///   - targetFormat: Optional target format to convert audio buffers to
    ///   - bufferHandler: Callback for audio buffers (called on audio thread)
    func start(
        skipSessionConfig: Bool = false,
        targetFormat: AVAudioFormat? = nil,
        bufferHandler: @escaping @Sendable (AVAudioPCMBuffer) -> Void
    ) async throws {
        currentBufferHandler = bufferHandler

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    #if os(iOS)
                    if !skipSessionConfig {
                        let audioSession = AVAudioSession.sharedInstance()
                        try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers, .allowBluetoothHFP])
                        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
                    }
                    #endif

                    let inputNode = audioEngine.inputNode
                    let recordingFormat = inputNode.outputFormat(forBus: 0)

                    guard recordingFormat.sampleRate > 0 else {
                        throw SpeechError.requestCreationFailed
                    }

                    // Install tap to capture audio
                    inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
                        guard let handler = self?.currentBufferHandler else { return }

                        // Convert buffer to target format if needed
                        if let targetFormat, let converted = Self.convertBuffer(buffer, to: targetFormat) {
                            handler(converted)
                        } else {
                            handler(buffer)
                        }
                    }

                    audioEngine.prepare()
                    try audioEngine.start()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Stop audio capture synchronously
    func stopSync(skipSessionDeactivation: Bool = false) {
        currentBufferHandler = nil
        queue.sync { [self] in
            if audioEngine.isRunning {
                audioEngine.stop()
            }
            audioEngine.inputNode.removeTap(onBus: 0)

            #if os(iOS)
            if !skipSessionDeactivation {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
            #endif
        }
    }

    /// Convert audio buffer to the target format
    private static func convertBuffer(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else { return nil }
        let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate)
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }

        var error: NSError?
        let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        return status == .haveData ? convertedBuffer : nil
    }
}

// MARK: - Authorization Helper

/// Non-isolated helper to request speech authorization without actor isolation context
/// This avoids dispatch queue assertion failures when the TCC callback runs on a background queue
@available(iOS 26.0, macOS 26.0, *)
private func requestSpeechAnalyzerAuthorizationStatus() async -> SFSpeechRecognizerAuthorizationStatus {
    await withCheckedContinuation { continuation in
        SFSpeechRecognizer.requestAuthorization { status in
            continuation.resume(returning: status)
        }
    }
}
