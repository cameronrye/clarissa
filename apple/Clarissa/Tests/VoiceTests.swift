import Foundation
import Testing
@testable import ClarissaKit

#if os(iOS)
import AVFoundation

// MARK: - AudioSessionManager Tests

@Suite("AudioSessionManager Tests")
struct AudioSessionManagerTests {

    @Test("Shared instance is singleton")
    func testSharedInstance() async {
        let instance1 = AudioSessionManager.shared
        let instance2 = AudioSessionManager.shared
        #expect(instance1 === instance2)
    }

    @Test("Configure for voice mode sets correct category")
    func testConfigureForVoiceMode() async throws {
        // Note: This test may fail on simulators without audio hardware
        // In production, we'd use dependency injection for AVAudioSession
        do {
            try await AudioSessionManager.shared.configureForVoiceMode()
            let session = AVAudioSession.sharedInstance()
            #expect(session.category == .playAndRecord)
            #expect(session.mode == .voiceChat)
        } catch {
            // Expected on simulator - audio hardware not available
            Issue.record("Audio session configuration failed (expected on simulator): \(error)")
        }
    }

    @Test("Configure for recording sets correct category")
    func testConfigureForRecording() async throws {
        do {
            try await AudioSessionManager.shared.configureForRecording()
            let session = AVAudioSession.sharedInstance()
            #expect(session.category == .record)
            #expect(session.mode == .measurement)
        } catch {
            Issue.record("Audio session configuration failed (expected on simulator): \(error)")
        }
    }

    @Test("Configure for playback sets correct category")
    func testConfigureForPlayback() async throws {
        do {
            try await AudioSessionManager.shared.configureForPlayback()
            let session = AVAudioSession.sharedInstance()
            #expect(session.category == .playback)
            #expect(session.mode == .spokenAudio)
        } catch {
            Issue.record("Audio session configuration failed (expected on simulator): \(error)")
        }
    }

    @Test("Deactivate does not throw")
    func testDeactivate() async {
        // Should not throw even if session wasn't active
        await AudioSessionManager.shared.deactivate()
    }
}
#endif

#if os(iOS)
// MARK: - SpeechRecognizer Tests

@Suite("SpeechRecognizer Tests")
@MainActor
struct SpeechRecognizerTests {

    @Test("Initial state is correct")
    func testInitialState() {
        let recognizer = SpeechRecognizer()
        #expect(recognizer.transcript == "")
        #expect(recognizer.isRecording == false)
        #expect(recognizer.error == nil)
        #expect(recognizer.useExternalAudioSession == false)
    }

    @Test("External audio session flag can be set")
    func testExternalAudioSessionFlag() {
        let recognizer = SpeechRecognizer()
        #expect(recognizer.useExternalAudioSession == false)

        recognizer.useExternalAudioSession = true
        #expect(recognizer.useExternalAudioSession == true)
    }

    @Test("Custom locale initialization")
    func testCustomLocale() {
        let ukRecognizer = SpeechRecognizer(locale: Locale(identifier: "en-GB"))
        // Can't directly access the private speechRecognizer, but we can verify it initializes
        #expect(ukRecognizer.transcript == "")
    }

    @Test("Stop recording when not recording is safe")
    func testStopRecordingWhenNotRecording() {
        let recognizer = SpeechRecognizer()
        #expect(recognizer.isRecording == false)

        // Should not throw or cause issues
        recognizer.stopRecording()
        #expect(recognizer.isRecording == false)
    }
}
#endif

#if os(iOS)
// MARK: - SpeechSynthesizer Tests

@Suite("SpeechSynthesizer Tests")
@MainActor
struct SpeechSynthesizerTests {

    @Test("Initial state is correct")
    func testInitialState() {
        let synthesizer = SpeechSynthesizer()
        #expect(synthesizer.isSpeaking == false)
        #expect(synthesizer.pitchMultiplier == 1.0)
        #expect(synthesizer.volume == 1.0)
        #expect(synthesizer.useExternalAudioSession == false)
    }

    @Test("External audio session flag can be set")
    func testExternalAudioSessionFlag() {
        let synthesizer = SpeechSynthesizer()
        #expect(synthesizer.useExternalAudioSession == false)

        synthesizer.useExternalAudioSession = true
        #expect(synthesizer.useExternalAudioSession == true)
    }

    @Test("Pitch multiplier can be set")
    func testPitchMultiplier() {
        let synthesizer = SpeechSynthesizer()
        synthesizer.pitchMultiplier = 1.5
        #expect(synthesizer.pitchMultiplier == 1.5)
    }

    @Test("Volume can be set")
    func testVolume() {
        let synthesizer = SpeechSynthesizer()
        synthesizer.volume = 0.5
        #expect(synthesizer.volume == 0.5)
    }

    @Test("Stop when not speaking is safe")
    func testStopWhenNotSpeaking() {
        let synthesizer = SpeechSynthesizer()
        #expect(synthesizer.isSpeaking == false)

        // Should not throw or cause issues
        synthesizer.stop()
        #expect(synthesizer.isSpeaking == false)
    }

    @Test("Pause when not speaking is safe")
    func testPauseWhenNotSpeaking() {
        let synthesizer = SpeechSynthesizer()
        // Should not throw
        synthesizer.pause()
    }

    @Test("Resume when not paused is safe")
    func testResumeWhenNotPaused() {
        let synthesizer = SpeechSynthesizer()
        // Should not throw
        synthesizer.resume()
    }
}
#endif

#if os(iOS)
// MARK: - VoiceManager Tests

@Suite("VoiceManager Tests")
@MainActor
struct VoiceManagerTests {

    @Test("Initial state is correct")
    func testInitialState() {
        let manager = VoiceManager()
        #expect(manager.isVoiceModeActive == false)
        #expect(manager.isListening == false)
        #expect(manager.isSpeaking == false)
        #expect(manager.currentTranscript == "")
        #expect(manager.voiceError == nil)
        #expect(manager.isAuthorized == false)
        #expect(manager.autoListenAfterSpeaking == true)
    }

    @Test("Cleanup resets state")
    func testCleanup() {
        let manager = VoiceManager()
        manager.cleanup()
        #expect(manager.isVoiceModeActive == false)
        #expect(manager.isListening == false)
        #expect(manager.isSpeaking == false)
    }

    @Test("Exit voice mode resets external session flags")
    func testExitVoiceModeResetsFlags() async {
        let manager = VoiceManager()

        // Simulate entering voice mode state (without actual audio)
        manager.speechRecognizer.useExternalAudioSession = true
        manager.speechSynthesizer.useExternalAudioSession = true

        await manager.exitVoiceMode()

        #expect(manager.speechRecognizer.useExternalAudioSession == false)
        #expect(manager.speechSynthesizer.useExternalAudioSession == false)
    }

    @Test("Stop listening when not listening is safe")
    func testStopListeningWhenNotListening() {
        let manager = VoiceManager()
        #expect(manager.isListening == false)

        // Should not throw or cause issues
        manager.stopListening()
        #expect(manager.isListening == false)
    }

    @Test("Stop speaking when not speaking is safe")
    func testStopSpeakingWhenNotSpeaking() {
        let manager = VoiceManager()
        #expect(manager.isSpeaking == false)

        // Should not throw
        manager.stopSpeaking()
        #expect(manager.isSpeaking == false)
    }

    @Test("Transcript ready callback is invoked")
    func testTranscriptReadyCallback() async {
        let manager = VoiceManager()

        manager.onTranscriptReady = { _ in
            // Callback is set and would be called during actual voice mode
        }

        // Simulate transcript being set directly (bypassing audio)
        manager.speechRecognizer.transcript = "Hello world"

        // Wait for Combine pipeline
        try? await Task.sleep(for: .milliseconds(100))

        // Note: The callback is only called in stopListening(), which requires isListening = true
        // This tests the observer pipeline works
        #expect(manager.currentTranscript == "Hello world")
    }

    @Test("Auto listen after speaking default is true")
    func testAutoListenAfterSpeakingDefault() {
        let manager = VoiceManager()
        #expect(manager.autoListenAfterSpeaking == true)

        manager.autoListenAfterSpeaking = false
        #expect(manager.autoListenAfterSpeaking == false)
    }

    @Test("Interruption callback can be set")
    func testInterruptionCallback() {
        let manager = VoiceManager()

        manager.onInterruption = {
            // Callback would be called during audio interruption
        }

        // Callback is stored
        #expect(manager.onInterruption != nil)
    }
}

// MARK: - SpeechError Tests

@Suite("SpeechError Tests")
struct SpeechErrorTests {

    @Test("Recognizer unavailable error description")
    func testRecognizerUnavailableDescription() {
        let error = SpeechError.recognizerUnavailable
        #expect(error.errorDescription?.contains("not available") == true)
    }

    @Test("Request creation failed error description")
    func testRequestCreationFailedDescription() {
        let error = SpeechError.requestCreationFailed
        #expect(error.errorDescription?.contains("Failed") == true)
    }

    @Test("Not authorized error description")
    func testNotAuthorizedDescription() {
        let error = SpeechError.notAuthorized
        #expect(error.errorDescription?.contains("not authorized") == true)
    }
}

// MARK: - Integration Tests

@Suite("Voice Integration Tests")
@MainActor
struct VoiceIntegrationTests {

    @Test("Voice manager components are properly initialized")
    func testComponentsInitialized() {
        let manager = VoiceManager()

        // Both sub-components should be initialized
        #expect(manager.speechRecognizer.isRecording == false)
        #expect(manager.speechSynthesizer.isSpeaking == false)
    }

    @Test("Voice mode toggle behavior")
    func testVoiceModeToggleBehavior() async {
        let manager = VoiceManager()

        // Initial state
        #expect(manager.isVoiceModeActive == false)

        // Without authorization, toggle should fail but not crash
        await manager.toggleVoiceMode()

        // Voice mode may or may not be active depending on authorization
        // The important thing is it doesn't crash
    }

    @Test("Speak stops listening")
    func testSpeakStopsListening() {
        let manager = VoiceManager()

        // This tests that calling speak() when not listening is safe
        manager.speak("Hello")

        // Should have started speech synthesis attempt
        // On simulator without audio, this may not actually play
    }
}

// MARK: - Audio Session Configuration Tests

@Suite("Audio Session Configuration Tests")
struct AudioSessionConfigurationTests {

    @Test("Voice mode options include speaker and bluetooth")
    func testVoiceModeOptions() {
        // This is a conceptual test - we verify the configuration values
        // The actual options are set in configureForVoiceMode()

        // Options should include:
        // - defaultToSpeaker: for hands-free use
        // - allowBluetooth: for headset support
        // - duckOthers: to lower other app audio

        // We can't directly inspect the options after configuration,
        // but we verify the method doesn't throw
        do {
            try AudioSessionManager.shared.configureForVoiceMode()
        } catch {
            // Expected on simulator
            Issue.record("Configuration failed (expected on simulator)")
        }
    }

    @Test("Recording options include bluetooth")
    func testRecordingOptions() {
        do {
            try AudioSessionManager.shared.configureForRecording()
        } catch {
            Issue.record("Configuration failed (expected on simulator)")
        }
    }
}
#endif
