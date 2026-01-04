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

        isRecording = true
        transcript = ""
        error = nil

        // Start audio capture on dedicated queue to avoid @MainActor isolation crash
        // The audio tap callback runs on a real-time audio thread
        // CRITICAL: The AsyncStream and continuation must be created and managed
        // entirely within the audio handler to avoid MainActor isolation issues
        let format = self.analyzerFormat
        let inputSequence = try await audioHandler.start(
            skipSessionConfig: useExternalAudioSession,
            targetFormat: format
        )

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

            self.stopRecordingInternal()
        }
    }

    /// Stop recording and finalize transcription
    private func stopRecordingInternal() {
        analysisTask?.cancel()
        analysisTask = nil

        // Stop audio capture on dedicated queue
        audioHandler.stop(skipSessionDeactivation: useExternalAudioSession)

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
///
/// CRITICAL FIX: The AsyncStream and its continuation are now created and managed entirely
/// within this handler class on its dedicated queue. This prevents the MainActor from being
/// involved in any audio callback operations, which was causing dispatch_assert_queue failures.
@available(iOS 26.0, macOS 26.0, *)
private final class SpeechAnalyzerAudioHandler: @unchecked Sendable {
    private let audioEngine = AVAudioEngine()
    private let queue = DispatchQueue(label: "com.clarissa.speechanalyzer.audio", qos: .userInitiated)

    // The continuation is stored here and managed on the audio queue
    // This ensures no MainActor involvement in audio callbacks
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var targetFormat: AVAudioFormat?

    /// Start audio capture and return an AsyncStream of AnalyzerInput
    /// - Parameters:
    ///   - skipSessionConfig: If true, skips audio session configuration (use when VoiceManager manages the session)
    ///   - targetFormat: Optional target format to convert audio buffers to
    /// - Returns: AsyncStream of AnalyzerInput for the SpeechAnalyzer
    func start(
        skipSessionConfig: Bool = false,
        targetFormat: AVAudioFormat? = nil
    ) async throws -> AsyncStream<AnalyzerInput> {
        self.targetFormat = targetFormat

        // Create the AsyncStream - the continuation will be stored and used on the audio queue
        let stream = AsyncStream<AnalyzerInput> { continuation in
            self.continuation = continuation
        }

        // Start audio engine on dedicated queue
        try await withCheckedThrowingContinuation { (startContinuation: CheckedContinuation<Void, Error>) in
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
                    // CRITICAL: The callback captures only self (the handler), not any MainActor state
                    // The continuation is accessed through self and is Sendable-safe
                    inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
                        guard let self, let continuation = self.continuation else { return }

                        // Convert buffer to target format if needed
                        let outputBuffer: AVAudioPCMBuffer
                        if let targetFormat = self.targetFormat,
                           let converted = Self.convertBuffer(buffer, to: targetFormat) {
                            outputBuffer = converted
                        } else {
                            outputBuffer = buffer
                        }

                        // Yield to the continuation - this is safe because continuation is Sendable
                        let input = AnalyzerInput(buffer: outputBuffer)
                        continuation.yield(input)
                    }

                    audioEngine.prepare()
                    try audioEngine.start()
                    startContinuation.resume()
                } catch {
                    startContinuation.resume(throwing: error)
                }
            }
        }

        return stream
    }

    /// Stop audio capture
    func stop(skipSessionDeactivation: Bool = false) {
        // Finish the continuation first
        continuation?.finish()
        continuation = nil
        targetFormat = nil

        // Stop audio engine on the dedicated queue
        queue.async { [self] in
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
