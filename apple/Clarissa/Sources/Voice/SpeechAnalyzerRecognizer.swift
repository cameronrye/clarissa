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
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var analyzerFormat: AVAudioFormat?

    // Audio capture
    private let audioEngine = AVAudioEngine()
    private let audioQueue = DispatchQueue(label: "com.clarissa.speechanalyzer", qos: .userInitiated)

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
        // SpeechAnalyzer uses the same authorization as SFSpeechRecognizer
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

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

        // Configure audio session (iOS only)
        #if os(iOS)
        if !useExternalAudioSession {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers, .allowBluetoothHFP])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        }
        #endif

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
        self.inputBuilder = continuation

        // Set up audio engine input
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.sampleRate > 0 else {
            throw SpeechError.requestCreationFailed
        }

        isRecording = true
        transcript = ""
        error = nil

        // Install tap to capture audio and feed to analyzer
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
            guard let self, let builder = self.inputBuilder else { return }
            // Convert buffer to analyzer format if needed and yield to stream
            if let format = self.analyzerFormat, let converted = self.convertBuffer(buffer, to: format) {
                let input = AnalyzerInput(buffer: converted)
                builder.yield(input)
            } else {
                // Use original buffer if no conversion needed
                let input = AnalyzerInput(buffer: buffer)
                builder.yield(input)
            }
        }

        // Start the audio engine
        audioEngine.prepare()
        try audioEngine.start()

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

    /// Convert audio buffer to the target format
    private func convertBuffer(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
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

    /// Stop recording and finalize transcription
    private func stopRecordingInternal() {
        // Finish the input stream to signal end of audio
        inputBuilder?.finish()
        inputBuilder = nil

        analysisTask?.cancel()
        analysisTask = nil

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        speechAnalyzer = nil
        speechTranscriber = nil
        analyzerFormat = nil
        isRecording = false

        // Deactivate audio session if we configured it
        #if os(iOS)
        if !useExternalAudioSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        #endif
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

