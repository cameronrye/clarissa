import Foundation
@preconcurrency import Speech
@preconcurrency import AVFoundation

/// Transcribes audio files using Apple's SpeechAnalyzer API (iOS 26+)
/// Supports MP3, M4A, WAV, CAF, and other common audio formats
@available(iOS 26.0, macOS 26.0, *)
@MainActor
final class AudioFileTranscriber: ObservableObject {
    @Published var transcript: String = ""
    @Published var isTranscribing: Bool = false
    @Published var progress: Double = 0
    @Published var error: String?

    private var transcriptionTask: Task<Void, Never>?
    private let locale: Locale

    /// Supported audio file extensions
    static let supportedExtensions = ["mp3", "m4a", "wav", "caf", "aac", "aiff", "flac"]

    init(locale: Locale = Locale.current) {
        self.locale = locale
    }

    /// Transcribe an audio file at the given URL
    /// - Parameter url: URL to the audio file (local file URL)
    /// - Returns: The transcribed text
    func transcribe(fileURL: URL) async throws -> String {
        guard fileURL.isFileURL else {
            throw AudioTranscriptionError.invalidURL
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw AudioTranscriptionError.fileNotFound
        }

        // Reset state
        transcript = ""
        progress = 0
        error = nil
        isTranscribing = true

        defer { isTranscribing = false }

        // Create transcriber with time-indexed preset for file transcription
        let transcriber = SpeechTranscriber(locale: locale, preset: .timeIndexedProgressiveTranscription)

        // Ensure the model is available
        try await ensureModel(transcriber: transcriber)

        // Create analyzer with the transcriber module
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        // Collect results in background while analyzing
        async let transcriptionFuture: String = {
            var result = ""
            for try await response in transcriber.results {
                if response.isFinal {
                    result += String(response.text.characters)
                }
            }
            return result
        }()

        // Open the audio file
        let audioFile = try AVAudioFile(forReading: fileURL)

        // Start analyzing the file
        if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            await analyzer.cancelAndFinishNow()
            throw AudioTranscriptionError.emptyAudio
        }

        // Get the final transcription
        let finalTranscript = try await transcriptionFuture
        transcript = finalTranscript
        progress = 1.0

        return finalTranscript
    }

    /// Cancel any ongoing transcription
    func cancel() {
        transcriptionTask?.cancel()
        transcriptionTask = nil
        isTranscribing = false
    }

    // MARK: - Model Management

    /// Ensure the speech model is downloaded and available
    private func ensureModel(transcriber: SpeechTranscriber) async throws {
        // Check if locale is supported
        let supported = await SpeechTranscriber.supportedLocales
        let isSupported = supported.contains { $0.identifier(.bcp47) == locale.identifier(.bcp47) }

        guard isSupported else {
            throw AudioTranscriptionError.localeNotSupported(locale)
        }

        // Check if model is installed
        let installed = await SpeechTranscriber.installedLocales
        let isInstalled = installed.contains { $0.identifier(.bcp47) == locale.identifier(.bcp47) }

        if !isInstalled {
            // Download the model
            if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await downloader.downloadAndInstall()
            }
        }
    }

    /// Check if a locale is supported for transcription
    static func isLocaleSupported(_ locale: Locale) async -> Bool {
        let supported = await SpeechTranscriber.supportedLocales
        return supported.contains { $0.identifier(.bcp47) == locale.identifier(.bcp47) }
    }

    /// Get list of supported locales
    static func supportedLocales() async -> [Locale] {
        await SpeechTranscriber.supportedLocales
    }
}

/// Errors specific to audio file transcription
enum AudioTranscriptionError: LocalizedError {
    case invalidURL
    case fileNotFound
    case emptyAudio
    case localeNotSupported(Locale)
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid file URL. Please provide a local file URL."
        case .fileNotFound:
            return "Audio file not found at the specified path."
        case .emptyAudio:
            return "The audio file appears to be empty or contains no speech."
        case .localeNotSupported(let locale):
            return "Language '\(locale.identifier)' is not supported for transcription."
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        }
    }
}

