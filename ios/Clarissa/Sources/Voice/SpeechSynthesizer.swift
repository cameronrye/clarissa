import Foundation
import AVFoundation

/// Handles text-to-speech using AVSpeechSynthesizer
@MainActor
final class SpeechSynthesizer: NSObject, ObservableObject {
    @Published var isSpeaking: Bool = false
    @Published var availableVoices: [AVSpeechSynthesisVoice] = []
    @Published var selectedVoiceIdentifier: String?

    private let synthesizer: AVSpeechSynthesizer
    private var currentUtterance: AVSpeechUtterance?

    /// Speech rate (0.0 to 1.0, default is 0.5)
    var rate: Float = AVSpeechUtteranceDefaultSpeechRate

    /// Pitch multiplier (0.5 to 2.0, default is 1.0)
    var pitchMultiplier: Float = 1.0

    /// Volume (0.0 to 1.0, default is 1.0)
    var volume: Float = 1.0

    override init() {
        synthesizer = AVSpeechSynthesizer()
        super.init()
        synthesizer.delegate = self
        loadAvailableVoices()
    }

    /// Load available voices for the current locale
    private func loadAvailableVoices() {
        // Get all voices and filter for quality
        let allVoices = AVSpeechSynthesisVoice.speechVoices()

        // Prefer enhanced/premium voices, then filter by English
        availableVoices = allVoices
            .filter { $0.language.starts(with: "en") }
            .sorted { voice1, voice2 in
                // Sort by quality (premium first)
                if voice1.quality != voice2.quality {
                    return voice1.quality.rawValue > voice2.quality.rawValue
                }
                return voice1.name < voice2.name
            }

        // Set default voice
        if selectedVoiceIdentifier == nil, let defaultVoice = availableVoices.first {
            selectedVoiceIdentifier = defaultVoice.identifier
        }
    }

    /// Get the currently selected voice
    var selectedVoice: AVSpeechSynthesisVoice? {
        guard let identifier = selectedVoiceIdentifier else {
            return AVSpeechSynthesisVoice(language: "en-US")
        }
        return AVSpeechSynthesisVoice(identifier: identifier)
    }

    /// Speak the given text
    func speak(_ text: String) {
        // Stop any current speech
        stop()

        // Configure audio session for playback
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
            try audioSession.setActive(true)
        } catch {
            ClarissaLogger.ui.error("Failed to configure audio session: \(error.localizedDescription)")
        }

        // Create utterance
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = selectedVoice
        utterance.rate = rate
        utterance.pitchMultiplier = pitchMultiplier
        utterance.volume = volume

        // Add slight pauses for more natural speech
        utterance.preUtteranceDelay = 0.1
        utterance.postUtteranceDelay = 0.1

        currentUtterance = utterance
        synthesizer.speak(utterance)
    }

    /// Stop speaking
    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        currentUtterance = nil
    }

    /// Pause speaking
    func pause() {
        if synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .word)
        }
    }

    /// Resume speaking
    func resume() {
        if synthesizer.isPaused {
            synthesizer.continueSpeaking()
        }
    }

    /// Get display name for a voice
    func displayName(for voice: AVSpeechSynthesisVoice) -> String {
        let quality = voice.quality == .enhanced ? " (Enhanced)" : ""
        return "\(voice.name)\(quality)"
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SpeechSynthesizer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = true
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.currentUtterance = nil

            // Deactivate audio session
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.currentUtterance = nil
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = true
        }
    }
}

