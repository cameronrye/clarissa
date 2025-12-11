import Foundation
import AVFoundation
import Speech
import Combine

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
    }

    // Note: deinit cannot access actor-isolated properties.
    // Use cleanup() before discarding VoiceManager to properly clean up resources.

    /// Clean up all voice resources - call before discarding VoiceManager
    func cleanup() {
        exitVoiceMode()
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

        isVoiceModeActive = true
        await startListening()
    }

    /// Exit voice mode
    func exitVoiceMode() {
        isVoiceModeActive = false
        stopListening()
        stopSpeaking()
    }

    /// Toggle voice mode
    func toggleVoiceMode() async {
        if isVoiceModeActive {
            exitVoiceMode()
        } else {
            await enterVoiceMode()
        }
    }
}

/// Non-isolated helper to request microphone permission without actor isolation context
/// This avoids dispatch queue assertion failures when the callback runs on a background queue
private func requestMicrophonePermission() async -> Bool {
    await withCheckedContinuation { continuation in
        AVAudioApplication.requestRecordPermission { granted in
            continuation.resume(returning: granted)
        }
    }
}
