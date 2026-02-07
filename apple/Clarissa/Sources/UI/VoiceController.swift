import Foundation
import Combine

/// Controls voice input/output lifecycle and bridges VoiceManager state to the view model
@MainActor
final class VoiceController {
    private(set) var voiceManager: VoiceManager?
    private var voiceCancellables = Set<AnyCancellable>()

    /// Callbacks for state changes
    var onRecordingChanged: ((Bool) -> Void)?
    var onTranscriptChanged: ((String) -> Void)?
    var onSpeakingChanged: ((Bool) -> Void)?
    var onVoiceModeChanged: ((Bool) -> Void)?
    var onTranscriptReady: ((String) -> Void)?

    /// Initialize voice manager and set up Combine subscriptions
    func setup() {
        let manager = VoiceManager()
        self.voiceManager = manager

        // Handle transcript ready
        manager.onTranscriptReady = { [weak self] transcript in
            Task { @MainActor [weak self] in
                self?.onTranscriptReady?(transcript)
            }
        }

        // Observe voice manager state using Combine
        manager.speechRecognizer.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isListening in
                self?.onRecordingChanged?(isListening)
            }
            .store(in: &voiceCancellables)

        manager.speechRecognizer.$transcript
            .receive(on: DispatchQueue.main)
            .sink { [weak self] transcript in
                self?.onTranscriptChanged?(transcript)
            }
            .store(in: &voiceCancellables)

        manager.speechSynthesizer.$isSpeaking
            .receive(on: DispatchQueue.main)
            .sink { [weak self] speaking in
                self?.onSpeakingChanged?(speaking)
            }
            .store(in: &voiceCancellables)

        manager.$isVoiceModeActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isActive in
                self?.onVoiceModeChanged?(isActive)
            }
            .store(in: &voiceCancellables)
    }

    // MARK: - Voice Control Methods

    func toggleVoiceInput() async {
        await voiceManager?.toggleListening()
    }

    func startVoiceInput() async {
        await voiceManager?.startListening()
    }

    func stopVoiceInputAndSend() {
        voiceManager?.stopListening()
    }

    func toggleVoiceMode() async {
        await voiceManager?.toggleVoiceMode()
    }

    func stopSpeaking() {
        voiceManager?.stopSpeaking()
    }

    func speak(_ text: String) {
        voiceManager?.speak(text)
    }

    func requestAuthorization() async -> Bool {
        guard let voiceManager = voiceManager else { return false }
        return await voiceManager.requestAuthorization()
    }
}
