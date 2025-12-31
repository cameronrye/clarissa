import Foundation
@preconcurrency import Speech
@preconcurrency import AVFoundation

/// Handles speech-to-text using Apple's Speech framework
/// Supports both iOS and macOS platforms
@MainActor
final class SpeechRecognizer: ObservableObject {
    @Published var transcript: String = ""
    @Published var isRecording: Bool = false
    @Published var isAvailable: Bool = false
    @Published var error: String?

    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    // Audio engine wrapper that handles operations on the correct queue
    private let audioHandler = AudioEngineHandler()

    /// Whether audio session is managed externally (e.g., by VoiceManager in voice mode)
    /// When true, the recognizer won't configure or deactivate the audio session
    /// Note: Only applicable on iOS where AVAudioSession exists
    var useExternalAudioSession: Bool = false

    init(locale: Locale = Locale(identifier: "en-US")) {
        speechRecognizer = SFSpeechRecognizer(locale: locale)
        isAvailable = speechRecognizer?.isAvailable ?? false
    }

    /// Request authorization for speech recognition
    func requestAuthorization() async -> Bool {
        let status = await requestSpeechAuthorizationStatus()

        // Update state on MainActor (we're already on MainActor due to class annotation)
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

    /// Start recording and transcribing speech
    func startRecording() async throws {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            throw SpeechError.recognizerUnavailable
        }

        // Cancel any existing task
        stopRecordingInternal()

        // Create recognition request
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        // Use on-device recognition for privacy
        request.requiresOnDeviceRecognition = speechRecognizer.supportsOnDeviceRecognition

        // Set task hint for better recognition accuracy
        request.taskHint = .dictation

        self.recognitionRequest = request

        // Start audio engine on dedicated queue (avoids dispatch queue assertion)
        // Skip session configuration if managed externally (e.g., voice mode) - iOS only
        try await audioHandler.start(skipSessionConfig: useExternalAudioSession) { [weak request] buffer in
            request?.append(buffer)
        }

        isRecording = true
        transcript = ""
        error = nil

        // Start recognition
        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, taskError in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }

                if let taskError {
                    self.error = taskError.localizedDescription
                    self.stopRecordingInternal()
                }

                if result?.isFinal == true {
                    self.stopRecordingInternal()
                }
            }
        }
    }

    /// Stop recording and finalize transcription (internal implementation)
    private func stopRecordingInternal() {
        let request = recognitionRequest
        let task = recognitionTask

        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false

        // Stop audio engine synchronously on dedicated queue
        // Skip session deactivation if managed externally (e.g., voice mode) - iOS only
        audioHandler.stopSync(skipSessionDeactivation: useExternalAudioSession)

        request?.endAudio()
        task?.cancel()
    }

    /// Stop recording and finalize transcription
    func stopRecording() {
        stopRecordingInternal()
    }

    /// Toggle recording state
    func toggleRecording() async {
        if isRecording {
            stopRecordingInternal()
        } else {
            do {
                try await startRecording()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

enum SpeechError: LocalizedError {
    case recognizerUnavailable
    case requestCreationFailed
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "Speech recognizer is not available"
        case .requestCreationFailed:
            return "Failed to create speech recognition request"
        case .notAuthorized:
            return "Speech recognition is not authorized"
        }
    }
}

/// Handles AVAudioEngine operations on a dedicated queue to avoid dispatch assertion failures
/// Works on both iOS and macOS - uses AVAudioSession on iOS only
///
/// Thread Safety: This class is @unchecked Sendable because it uses manual synchronization:
/// - `engineLock` (NSLock) protects `isReconfiguring` and audio engine state transitions
/// - `queue` serializes all audio engine operations
/// - Mutable callbacks are only accessed from the serialized queue
private final class AudioEngineHandler: @unchecked Sendable {
    private let audioEngine = AVAudioEngine()
    private let queue = DispatchQueue(label: "com.clarissa.audioengine", qos: .userInitiated)

    /// Lock to synchronize audio engine operations during configuration changes
    private let engineLock = NSLock()

    /// Flag to indicate if we're in the middle of a configuration change
    private var isReconfiguring = false

    /// Callback to notify when audio engine needs restart (e.g., after system reconfiguration)
    var onConfigurationChange: (() -> Void)?

    /// Current buffer handler for restart scenarios
    private var currentBufferHandler: (@Sendable (AVAudioPCMBuffer) -> Void)?

    init() {
        setupConfigurationChangeObserver()
    }

    /// Set up observer for audio engine configuration changes (system resets)
    private func setupConfigurationChangeObserver() {
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            // Configuration changed - engine needs to be reconfigured
            // This can happen when audio route changes or system reclaims resources
            self.queue.async {
                // Acquire lock before modifying audio engine state
                self.engineLock.lock()
                defer { self.engineLock.unlock() }

                // Mark that we're reconfiguring to prevent concurrent operations
                self.isReconfiguring = true
                defer { self.isReconfiguring = false }

                if self.audioEngine.isRunning {
                    self.audioEngine.stop()
                }
                self.audioEngine.inputNode.removeTap(onBus: 0)

                // Notify that configuration changed (caller may want to restart)
                self.onConfigurationChange?()
            }
        }
    }

    /// Start audio capture
    /// - Parameters:
    ///   - skipSessionConfig: If true, skips audio session configuration (iOS only, use when VoiceManager has already configured it)
    ///   - bufferHandler: Callback for audio buffers
    func start(
        skipSessionConfig: Bool = false,
        bufferHandler: @escaping @Sendable (AVAudioPCMBuffer) -> Void
    ) async throws {
        // Store handler for potential restart scenarios
        currentBufferHandler = bufferHandler

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                // Acquire lock to synchronize with configuration changes
                engineLock.lock()
                defer { engineLock.unlock() }

                // Check if we're in the middle of reconfiguration
                guard !isReconfiguring else {
                    continuation.resume(throwing: SpeechError.requestCreationFailed)
                    return
                }

                do {
                    // Stop any existing session first
                    if audioEngine.isRunning {
                        audioEngine.stop()
                    }
                    audioEngine.inputNode.removeTap(onBus: 0)

                    // Configure audio session (iOS only)
                    #if os(iOS)
                    if !skipSessionConfig {
                        let audioSession = AVAudioSession.sharedInstance()
                        try audioSession.setCategory(
                            .record,
                            mode: .measurement,
                            options: [.duckOthers, .allowBluetoothHFP]
                        )
                        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
                    }
                    #endif

                    // Set up audio input
                    let inputNode = audioEngine.inputNode
                    let recordingFormat = inputNode.outputFormat(forBus: 0)

                    // Validate format before installing tap
                    guard recordingFormat.sampleRate > 0 else {
                        throw SpeechError.requestCreationFailed
                    }

                    inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                        bufferHandler(buffer)
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

    /// Stop audio capture
    /// - Parameter skipSessionDeactivation: If true, skips audio session deactivation (iOS only, use when VoiceManager manages the session)
    func stop(skipSessionDeactivation: Bool = false) async {
        currentBufferHandler = nil
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                // Acquire lock to synchronize with configuration changes
                engineLock.lock()
                defer { engineLock.unlock() }

                if audioEngine.isRunning {
                    audioEngine.stop()
                }
                audioEngine.inputNode.removeTap(onBus: 0)

                #if os(iOS)
                if !skipSessionDeactivation {
                    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                }
                #endif
                continuation.resume()
            }
        }
    }

    /// Stop audio capture synchronously
    /// - Parameter skipSessionDeactivation: If true, skips audio session deactivation (iOS only, use when VoiceManager manages the session)
    func stopSync(skipSessionDeactivation: Bool = false) {
        currentBufferHandler = nil
        queue.sync { [self] in
            // Acquire lock to synchronize with configuration changes
            engineLock.lock()
            defer { engineLock.unlock() }

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

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

/// Non-isolated helper to request speech authorization without actor isolation context
/// This avoids dispatch queue assertion failures when the callback runs on a background queue
private func requestSpeechAuthorizationStatus() async -> SFSpeechRecognizerAuthorizationStatus {
    await withCheckedContinuation { continuation in
        SFSpeechRecognizer.requestAuthorization { status in
            continuation.resume(returning: status)
        }
    }
}
