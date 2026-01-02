import Foundation
import AVFoundation

/// Handles text-to-speech using AVSpeechSynthesizer
/// Works on both iOS and macOS platforms
@MainActor
final class SpeechSynthesizer: NSObject, ObservableObject {
    @Published var isSpeaking: Bool = false
    @Published var availableVoices: [AVSpeechSynthesisVoice] = []

    private let synthesizer: AVSpeechSynthesizer
    private var currentUtterance: AVSpeechUtterance?

    /// Pitch multiplier (0.5 to 2.0, default is 1.0)
    var pitchMultiplier: Float = 1.0

    /// Volume (0.0 to 1.0, default is 1.0)
    var volume: Float = 1.0

    /// Whether audio session is managed externally (e.g., by VoiceManager in voice mode)
    /// When true, the synthesizer won't configure or deactivate the audio session
    /// Note: Only applicable on iOS where AVAudioSession exists
    var useExternalAudioSession: Bool = false

    // MARK: - UserDefaults Keys (matching SettingsView)
    private static let voiceIdentifierKey = "selectedVoiceIdentifier"
    private static let speechRateKey = "speechRate"

    override init() {
        synthesizer = AVSpeechSynthesizer()
        super.init()
        synthesizer.delegate = self
        loadAvailableVoices()
    }

    /// Load available voices with fallback
    private func loadAvailableVoices() {
        // Get preferred languages from system (more reliable than Locale.current)
        let preferredLanguages = Locale.preferredLanguages
        let primaryLanguage = preferredLanguages.first?.split(separator: "-").first.map(String.init) ?? "en"

        let allVoices = AVSpeechSynthesisVoice.speechVoices()

        // Filter voices matching user's language preference
        let languageMatchedVoices = allVoices.filter { voice in
            voice.language.hasPrefix(primaryLanguage)
        }

        // Try to get high-quality voices first (Premium/Enhanced)
        let highQualityVoices = languageMatchedVoices
            .filter { voice in
                voice.quality == .premium || voice.quality == .enhanced
            }
            .sorted { voice1, voice2 in
                // Sort: Premium first, then Enhanced, then alphabetically
                if voice1.quality != voice2.quality {
                    return voice1.quality.rawValue > voice2.quality.rawValue
                }
                return voice1.name < voice2.name
            }

        // Fallback: if no high-quality voices, show all voices for the language
        // sorted by quality (best first)
        if highQualityVoices.isEmpty {
            availableVoices = languageMatchedVoices.sorted { voice1, voice2 in
                if voice1.quality != voice2.quality {
                    return voice1.quality.rawValue > voice2.quality.rawValue
                }
                return voice1.name < voice2.name
            }
        } else {
            availableVoices = highQualityVoices
        }
    }

    /// Get the voice identifier from UserDefaults (set by SettingsView)
    private var selectedVoiceIdentifier: String? {
        let stored = UserDefaults.standard.string(forKey: Self.voiceIdentifierKey)
        // Return nil if empty string (means "System Default")
        return (stored?.isEmpty == false) ? stored : nil
    }

    /// Get the speech rate from UserDefaults (set by SettingsView)
    /// Returns a value between 0.0 and 1.0, converted to AVSpeechUtterance rate
    private var speechRate: Float {
        let storedRate = UserDefaults.standard.double(forKey: Self.speechRateKey)
        // Default to 0.5 if not set (normal speed)
        let normalizedRate = storedRate > 0 ? storedRate : 0.5
        // Convert 0.0-1.0 to AVSpeechUtterance rate range
        // AVSpeechUtteranceMinimumSpeechRate = 0.0, AVSpeechUtteranceMaximumSpeechRate = 1.0
        // But the actual usable range is typically 0.0 to 0.7 for natural speech
        return Float(normalizedRate) * AVSpeechUtteranceMaximumSpeechRate
    }

    /// Get the currently selected voice from UserDefaults
    var selectedVoice: AVSpeechSynthesisVoice? {
        if let identifier = selectedVoiceIdentifier,
           let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            return voice
        }
        // Fallback: try to use the first available high-quality voice
        if let firstVoice = availableVoices.first {
            return firstVoice
        }
        // Final fallback: use system default for en-US
        return AVSpeechSynthesisVoice(language: "en-US")
    }

    /// Speak the given text
    func speak(_ text: String) {
        // Stop any current speech
        stop()

        // Configure audio session for playback (iOS only, skip if managed externally)
        #if os(iOS)
        if !useExternalAudioSession {
            do {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
                try audioSession.setActive(true)
            } catch {
                ClarissaLogger.ui.error("Failed to configure audio session: \(error.localizedDescription)")
            }
        }
        #endif

        // Create utterance with settings from UserDefaults
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = selectedVoice
        utterance.rate = speechRate
        utterance.pitchMultiplier = pitchMultiplier
        utterance.volume = volume

        // Add slight pauses for more natural speech
        utterance.preUtteranceDelay = 0.1
        utterance.postUtteranceDelay = 0.1

        ClarissaLogger.ui.debug("Speaking with voice: \(utterance.voice?.name ?? "System Default"), rate: \(utterance.rate)")

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

    /// Get display name for a voice with quality indicators
    func displayName(for voice: AVSpeechSynthesisVoice) -> String {
        let qualityIndicator: String
        switch voice.quality {
        case .premium: qualityIndicator = " (Premium)"
        case .enhanced: qualityIndicator = " (Enhanced)"
        default: qualityIndicator = ""
        }
        // Extract region from language code (e.g., "en-US" → "US")
        let region = voice.language.split(separator: "-").dropFirst().first.map { " (\($0))" } ?? ""
        return "\(voice.name)\(region)\(qualityIndicator)"
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

            // Deactivate audio session (iOS only, skip if managed externally)
            #if os(iOS)
            if !self.useExternalAudioSession {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
            #endif
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.currentUtterance = nil

            // Deactivate audio session (iOS only, skip if managed externally)
            #if os(iOS)
            if !self.useExternalAudioSession {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
            #endif
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
