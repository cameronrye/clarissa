import Foundation
import AVFoundation
import Speech
import SwiftUI

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

    init() {
        speechRecognizer = SpeechRecognizer()
        speechSynthesizer = SpeechSynthesizer()
        setupObservers()
    }

    private func setupObservers() {
        // Observe speech recognizer state
        Task { @MainActor in
            for await isRecording in speechRecognizer.$isRecording.values {
                self.isListening = isRecording
            }
        }

        Task { @MainActor in
            for await transcript in speechRecognizer.$transcript.values {
                self.currentTranscript = transcript
            }
        }

        Task { @MainActor in
            for await isSpeaking in speechSynthesizer.$isSpeaking.values {
                self.isSpeaking = isSpeaking

                // Auto-listen after speaking in voice mode
                if !isSpeaking && self.isVoiceModeActive && self.autoListenAfterSpeaking {
                    try? await Task.sleep(for: .milliseconds(500))
                    if self.isVoiceModeActive && !self.isListening {
                        await self.startListening()
                    }
                }
            }
        }
    }

    /// Request necessary permissions for voice features
    func requestAuthorization() async -> Bool {
        // Request speech recognition permission
        let speechAuthorized = await speechRecognizer.requestAuthorization()

        // Request microphone permission
        let micAuthorized = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }

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

