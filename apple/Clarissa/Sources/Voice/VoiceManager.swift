import Foundation
import AVFoundation
import Speech
import Combine

#if os(iOS)
// MARK: - Audio Session Manager (iOS)

/// Manages audio session configuration for voice mode on iOS
/// Uses .playAndRecord category to avoid switching between record and playback
/// Note: Uses actor isolation for thread-safe audio session configuration
actor AudioSessionManager {
    static let shared = AudioSessionManager()

    private init() {}

    /// Configure audio session for voice conversation mode (both recording and playback)
    /// This avoids constantly switching categories during a conversation
    func configureForVoiceMode() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetoothHFP, .duckOthers]
        )
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    /// Configure audio session for recording only
    func configureForRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .record,
            mode: .measurement,
            options: [.duckOthers, .allowBluetoothHFP]
        )
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    /// Configure audio session for playback only
    func configureForPlayback() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playback,
            mode: .spokenAudio,
            options: .duckOthers
        )
        try session.setActive(true)
    }

    /// Deactivate audio session
    func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
#else
// MARK: - Audio Session Manager (macOS)

/// macOS doesn't have AVAudioSession - audio is managed at the system level
/// This is a no-op implementation that maintains API compatibility
actor AudioSessionManager {
    static let shared = AudioSessionManager()

    private init() {}

    /// No-op on macOS - system manages audio routing
    func configureForVoiceMode() throws {
        // macOS handles audio routing automatically
        ClarissaLogger.ui.debug("Voice mode audio configuration not needed on macOS")
    }

    /// No-op on macOS
    func configureForRecording() throws {
        ClarissaLogger.ui.debug("Recording audio configuration not needed on macOS")
    }

    /// No-op on macOS
    func configureForPlayback() throws {
        ClarissaLogger.ui.debug("Playback audio configuration not needed on macOS")
    }

    /// No-op on macOS
    func deactivate() {
        ClarissaLogger.ui.debug("Audio session deactivation not needed on macOS")
    }
}
#endif

// MARK: - Voice Manager

/// Coordinates voice input and output for conversational voice mode
@MainActor
final class VoiceManager: ObservableObject {
    @Published var isVoiceModeActive: Bool = false
    @Published var isListening: Bool = false
    @Published var isSpeaking: Bool = false
    @Published var currentTranscript: String = ""
    @Published var voiceError: String?
    @Published var isAuthorized: Bool = false

    let speechRecognizer: SpeechRecognizer
    let speechSynthesizer: SpeechSynthesizer

    /// Whether to automatically listen after speaking (conversational mode)
    var autoListenAfterSpeaking: Bool = true

    /// Callback when transcript is finalized and ready to send
    var onTranscriptReady: ((String) -> Void)?

    /// Callback when user interrupts speech
    var onInterruption: (() -> Void)?

    private var cancellables = Set<AnyCancellable>()

    init() {
        speechRecognizer = SpeechRecognizer()
        speechSynthesizer = SpeechSynthesizer()
        setupObservers()
        setupAudioSessionObservers()
    }

    // Note: deinit cannot access actor-isolated properties.
    // Use cleanup() before discarding VoiceManager to properly clean up resources.

    /// Clean up all voice resources - call before discarding VoiceManager
    func cleanup() async {
        await exitVoiceMode()
        cancellables.removeAll()
    }

    private func setupObservers() {
        // Observe speech recognizer state using Combine
        speechRecognizer.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRecording in
                self?.isListening = isRecording
            }
            .store(in: &cancellables)

        speechRecognizer.$transcript
            .receive(on: DispatchQueue.main)
            .sink { [weak self] transcript in
                self?.currentTranscript = transcript
            }
            .store(in: &cancellables)

        speechSynthesizer.$isSpeaking
            .receive(on: DispatchQueue.main)
            .sink { [weak self] speaking in
                guard let self else { return }
                self.isSpeaking = speaking

                // Auto-listen after speaking in voice mode
                if !speaking && self.isVoiceModeActive && self.autoListenAfterSpeaking {
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .milliseconds(500))
                        guard let self, self.isVoiceModeActive, !self.isListening else { return }
                        await self.startListening()
                    }
                }
            }
            .store(in: &cancellables)
    }

    /// Request necessary permissions for voice features
    func requestAuthorization() async -> Bool {
        // Request speech recognition permission
        let speechAuthorized = await speechRecognizer.requestAuthorization()

        // Request microphone permission (use non-isolated helper to avoid dispatch queue assertion)
        let micAuthorized = await requestMicrophonePermission()

        isAuthorized = speechAuthorized && micAuthorized
        return isAuthorized
    }

    /// Check if voice features are available
    var isAvailable: Bool {
        speechRecognizer.isAvailable
    }

    /// Start listening for voice input
    func startListening() async {
        if !isAuthorized {
            let authorized = await requestAuthorization()
            if !authorized {
                voiceError = "Voice input requires microphone and speech recognition permissions"
                return
            }
        }

        // If speaking, stop and treat as interruption
        if isSpeaking {
            speechSynthesizer.stop()
            onInterruption?()
        }

        voiceError = nil
        await speechRecognizer.toggleRecording()
    }

    /// Stop listening and finalize transcript
    func stopListening() {
        guard isListening else { return }

        speechRecognizer.stopRecording()

        // Notify that transcript is ready
        let transcript = currentTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !transcript.isEmpty {
            onTranscriptReady?(transcript)
        }
    }

    /// Toggle listening state
    func toggleListening() async {
        if isListening {
            stopListening()
        } else {
            await startListening()
        }
    }

    /// Speak text using text-to-speech
    func speak(_ text: String) {
        // Stop listening if active
        if isListening {
            speechRecognizer.stopRecording()
        }

        speechSynthesizer.speak(text)
    }

    /// Stop speaking
    func stopSpeaking() {
        speechSynthesizer.stop()
    }

    /// Enter voice mode (full hands-free conversation)
    func enterVoiceMode() async {
        guard await requestAuthorization() else {
            voiceError = "Unable to start voice mode without permissions"
            return
        }

        // Configure audio session for bidirectional voice conversation
        // Using .playAndRecord avoids switching categories during conversation
        do {
            try await AudioSessionManager.shared.configureForVoiceMode()
        } catch {
            ClarissaLogger.ui.error("Failed to configure voice mode audio session: \(error.localizedDescription)")
            voiceError = "Failed to configure audio for voice mode"
            return
        }

        // Tell components that we're managing the audio session
        speechRecognizer.useExternalAudioSession = true
        speechSynthesizer.useExternalAudioSession = true

        isVoiceModeActive = true
        await startListening()
    }

    /// Exit voice mode
    func exitVoiceMode() async {
        isVoiceModeActive = false

        // Restore normal audio session management
        speechRecognizer.useExternalAudioSession = false
        speechSynthesizer.useExternalAudioSession = false

        stopListening()
        stopSpeaking()

        // Deactivate audio session when exiting voice mode
        await AudioSessionManager.shared.deactivate()
    }

    /// Toggle voice mode
    func toggleVoiceMode() async {
        if isVoiceModeActive {
            await exitVoiceMode()
        } else {
            await enterVoiceMode()
        }
    }

    // MARK: - Audio Session Management

    /// Set up observers for audio interruptions and route changes
    /// Note: These are iOS-only; macOS handles audio routing at the system level
    private func setupAudioSessionObservers() {
        #if os(iOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        #endif
    }

    #if os(iOS)
    /// Handle audio interruptions (phone calls, Siri, alarms, etc.)
    /// Note: This notification can arrive on any thread, so we dispatch to MainActor
    @objc nonisolated private func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        // Extract interruption options before entering the Task to avoid data races
        // (userInfo dictionary cannot be safely sent across actor boundaries)
        let interruptionOptions: AVAudioSession.InterruptionOptions?
        if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
            interruptionOptions = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
        } else {
            interruptionOptions = nil
        }

        Task { @MainActor [weak self] in
            guard let self else { return }

            switch type {
            case .began:
                // Interruption began - pause all audio activities
                ClarissaLogger.ui.info("Audio interruption began - pausing voice activities")
                if self.isListening {
                    self.speechRecognizer.stopRecording()
                }
                if self.isSpeaking {
                    self.speechSynthesizer.stop()
                }

            case .ended:
                // Interruption ended - check if we should resume
                guard let options = interruptionOptions else {
                    return
                }

                if options.contains(.shouldResume) {
                    ClarissaLogger.ui.info("Audio interruption ended - resuming voice mode")
                    // Resume listening if in voice mode
                    if self.isVoiceModeActive && !self.isListening {
                        try? await Task.sleep(for: .milliseconds(300))
                        await self.startListening()
                    }
                }

            @unknown default:
                break
            }
        }
    }

    /// Handle audio route changes (headphones unplugged, Bluetooth connected, etc.)
    /// Note: This notification can arrive on any thread, so we dispatch to MainActor
    @objc nonisolated private func handleAudioRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }

            switch reason {
            case .oldDeviceUnavailable:
                // Headphones unplugged - stop playback per Apple HIG
                ClarissaLogger.ui.info("Audio device unavailable - stopping speech")
                self.speechSynthesizer.stop()

            case .newDeviceAvailable:
                // New audio device connected (headphones, Bluetooth)
                ClarissaLogger.ui.info("New audio device available")

            case .categoryChange:
                // Audio category changed by another app
                ClarissaLogger.ui.debug("Audio category changed")

            default:
                break
            }
        }
    }
    #endif
}

/// Non-isolated helper to request microphone permission without actor isolation context
/// This avoids dispatch queue assertion failures when the callback runs on a background queue
private func requestMicrophonePermission() async -> Bool {
    #if os(iOS)
    return await withCheckedContinuation { continuation in
        AVAudioApplication.requestRecordPermission { granted in
            continuation.resume(returning: granted)
        }
    }
    #else
    // On macOS, check system microphone permission
    return await withCheckedContinuation { continuation in
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            continuation.resume(returning: true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        case .denied, .restricted:
            continuation.resume(returning: false)
        @unknown default:
            continuation.resume(returning: false)
        }
    }
    #endif
}
