import SwiftUI
import AVFoundation

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var appState: AppState
    @AppStorage("selectedModel") private var selectedModel: String = "anthropic/claude-sonnet-4"
    @AppStorage("voiceOutputEnabled") private var voiceOutputEnabled: Bool = true
    @AppStorage("selectedVoiceIdentifier") private var selectedVoiceIdentifier: String = ""
    @AppStorage("speechRate") private var speechRate: Double = 0.5

    @State private var openRouterApiKey: String = ""
    @State private var showingApiKey = false
    @State private var memories: [Memory] = []
    @State private var showMemories = false
    @State private var showingSaveConfirmation = false
    @State private var availableVoices: [AVSpeechSynthesisVoice] = []
    @State private var testSynthesizer: AVSpeechSynthesizer?

    // Namespace for glass morphing in settings
    @Namespace private var settingsNamespace

    public var onProviderChange: (() -> Void)?

    public init(onProviderChange: (() -> Void)? = nil) {
        self.onProviderChange = onProviderChange
    }

    private let availableModels = [
        "anthropic/claude-sonnet-4",
        "anthropic/claude-opus-4",
        "openai/gpt-4o",
        "openai/gpt-4o-mini",
        "google/gemini-2.0-flash",
        "meta-llama/llama-3.3-70b-instruct"
    ]

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    providerPicker
                } header: {
                    Text("LLM Provider")
                } footer: {
                    Text("Choose between on-device AI or cloud-based models.")
                }

                Section {
                    HStack {
                        if showingApiKey {
                            TextField("API Key", text: $openRouterApiKey)
                                .textContentType(.password)
                                .autocorrectionDisabled()
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                #endif
                                .onChange(of: openRouterApiKey) { _, newValue in
                                    saveApiKey(newValue)
                                }
                        } else {
                            SecureField("API Key", text: $openRouterApiKey)
                                .onChange(of: openRouterApiKey) { _, newValue in
                                    saveApiKey(newValue)
                                }
                        }

                        Button {
                            showingApiKey.toggle()
                        } label: {
                            Image(systemName: showingApiKey ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Picker("Model", selection: $selectedModel) {
                        ForEach(availableModels, id: \.self) { model in
                            Text(formatModelName(model))
                                .tag(model)
                        }
                    }

                    Link("Get API Key", destination: URL(string: "https://openrouter.ai/keys")!)
                        .foregroundStyle(ClarissaTheme.cyan)
                } header: {
                    Text("OpenRouter (Cloud)")
                } footer: {
                    Text("API key is stored securely in the Keychain.")
                }

                Section {
                    NavigationLink {
                        ToolSettingsView()
                            .environmentObject(appState)
                    } label: {
                        HStack {
                            Image(systemName: "wrench.and.screwdriver")
                                .foregroundStyle(ClarissaTheme.purple)
                            Text("Configure Tools")
                            Spacer()
                            Text("\(ToolSettings.shared.enabledCount) enabled")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Tools")
                } footer: {
                    Text("Configure which tools are available to the assistant.")
                }

                Section {
                    NavigationLink {
                        MemoryListView(memories: $memories)
                    } label: {
                        HStack {
                            Image(systemName: "brain.head.profile")
                                .foregroundStyle(ClarissaTheme.purple)
                            Text("Memories")
                            Spacer()
                            Text("\(memories.count)")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button(role: .destructive) {
                        Task {
                            await MemoryManager.shared.clear()
                            memories = []
                        }
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Clear All Memories")
                        }
                    }
                } header: {
                    Text("Long-term Memory")
                }

                Section {
                    Toggle(isOn: $voiceOutputEnabled) {
                        HStack {
                            Image(systemName: "speaker.wave.2")
                                .foregroundStyle(ClarissaTheme.cyan)
                            Text("Voice Output")
                        }
                    }

                    if voiceOutputEnabled {
                        Picker("Voice", selection: $selectedVoiceIdentifier) {
                            Text("System Default").tag("")
                            ForEach(availableVoices, id: \.identifier) { voice in
                                Text(voiceDisplayName(for: voice))
                                    .tag(voice.identifier)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Speech Rate")
                                Spacer()
                                Text(speechRateLabel)
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $speechRate, in: 0.0...1.0, step: 0.1)
                                .tint(ClarissaTheme.purple)
                        }

                        Button {
                            testVoice()
                        } label: {
                            HStack {
                                Image(systemName: "play.circle")
                                    .foregroundStyle(ClarissaTheme.purple)
                                Text("Test Voice")
                            }
                        }
                    }
                } header: {
                    Text("Voice")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("When enabled, Clarissa will speak responses aloud in voice mode.")
                        if voiceOutputEnabled && availableVoices.isEmpty {
                            #if os(macOS)
                            Text("No high-quality voices found. Download Siri voices in System Settings → Accessibility → Spoken Content → System Voices.")
                                .foregroundStyle(.orange)
                            #else
                            Text("No high-quality voices found. Download Siri voices in Settings → Accessibility → Spoken Content → Voices.")
                                .foregroundStyle(.orange)
                            #endif
                        } else if voiceOutputEnabled {
                            #if os(macOS)
                            Text("★ = Premium quality. Download more voices in System Settings → Accessibility → Spoken Content → System Voices.")
                            #else
                            Text("★ = Premium quality. Download more voices in Settings → Accessibility → Spoken Content → Voices.")
                            #endif
                        }
                    }
                }

                #if os(macOS)
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("New Conversation")
                            Spacer()
                            Text("⌘N")
                                .foregroundStyle(.secondary)
                                .font(.system(.body, design: .monospaced))
                        }
                        HStack {
                            Text("Clear Conversation")
                            Spacer()
                            Text("⇧⌘⌫")
                                .foregroundStyle(.secondary)
                                .font(.system(.body, design: .monospaced))
                        }
                        HStack {
                            Text("Cancel Generation")
                            Spacer()
                            Text("Esc")
                                .foregroundStyle(.secondary)
                                .font(.system(.body, design: .monospaced))
                        }
                        HStack {
                            Text("Settings")
                            Spacer()
                            Text("⌘,")
                                .foregroundStyle(.secondary)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                    .font(.subheadline)
                } header: {
                    HStack {
                        Image(systemName: "keyboard")
                            .foregroundStyle(ClarissaTheme.cyan)
                        Text("Keyboard Shortcuts")
                    }
                }
                #endif

                Section {
                    Button {
                        appState.resetOnboarding()
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "book.pages")
                                .foregroundStyle(ClarissaTheme.purple)
                            Text("View Tutorial")
                        }
                    }
                } header: {
                    Text("Help")
                }

                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }

                    Link(destination: URL(string: "https://rye.dev")!) {
                        HStack {
                            Text("Made with \u{2764}\u{FE0F} by Cameron Rye")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #if os(macOS)
            .formStyle(.grouped)
            .frame(minWidth: 500, idealWidth: 600, maxWidth: 800)
            #endif
        }
        .tint(ClarissaTheme.purple)
        .task {
            memories = await MemoryManager.shared.getAll()
            // Load API key from Keychain
            openRouterApiKey = KeychainManager.shared.get(key: KeychainManager.Keys.openRouterApiKey) ?? ""
            // Load available voices
            loadAvailableVoices()
        }
    }

    // MARK: - Voice Helpers

    private func loadAvailableVoices() {
        // Only load high-quality Siri voices (Premium/Enhanced)
        // These must be downloaded in Settings > Accessibility > Spoken Content > Voices
        let preferredLanguage = Locale.current.language.languageCode?.identifier ?? "en"

        availableVoices = AVSpeechSynthesisVoice.speechVoices()
            .filter { voice in
                // Only Premium or Enhanced quality (high-quality Siri voices)
                voice.quality == .premium || voice.quality == .enhanced
            }
            .filter { voice in
                // Match user's language preference
                voice.language.hasPrefix(preferredLanguage)
            }
            .sorted { voice1, voice2 in
                // Sort: Premium first, then Enhanced, then alphabetically
                if voice1.quality != voice2.quality {
                    return voice1.quality.rawValue > voice2.quality.rawValue
                }
                return voice1.name < voice2.name
            }
    }

    private func voiceDisplayName(for voice: AVSpeechSynthesisVoice) -> String {
        let qualityIndicator: String
        switch voice.quality {
        case .premium: qualityIndicator = " ★"
        case .enhanced: qualityIndicator = ""
        default: qualityIndicator = ""
        }
        // Extract region from language code (e.g., "en-US" → "US")
        let region = voice.language.split(separator: "-").dropFirst().first.map { " (\($0))" } ?? ""
        return "\(voice.name)\(region)\(qualityIndicator)"
    }

    private var speechRateLabel: String {
        switch speechRate {
        case 0.0..<0.3: return "Slow"
        case 0.3..<0.6: return "Normal"
        case 0.6..<0.8: return "Fast"
        default: return "Very Fast"
        }
    }

    private func testVoice() {
        // Create and retain synthesizer to prevent deallocation during playback
        let synthesizer = AVSpeechSynthesizer()
        testSynthesizer = synthesizer

        let utterance = AVSpeechUtterance(string: "Hello, I'm Clarissa, your AI assistant.")
        utterance.rate = Float(speechRate) * AVSpeechUtteranceMaximumSpeechRate

        if !selectedVoiceIdentifier.isEmpty,
           let voice = AVSpeechSynthesisVoice(identifier: selectedVoiceIdentifier) {
            utterance.voice = voice
        }

        synthesizer.speak(utterance)
    }

    /// Save API key to Keychain (debounced)
    private func saveApiKey(_ value: String) {
        // Only save non-empty values
        if value.isEmpty {
            try? KeychainManager.shared.delete(key: KeychainManager.Keys.openRouterApiKey)
        } else {
            try? KeychainManager.shared.set(value, forKey: KeychainManager.Keys.openRouterApiKey)
        }
    }

    @ViewBuilder
    private var providerPicker: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            glassProviderPicker
        } else {
            legacyProviderPicker
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    private var glassProviderPicker: some View {
        GlassEffectContainer(spacing: 12) {
            ForEach(LLMProviderType.allCases) { provider in
                Button {
                    HapticManager.shared.selection()
                    appState.selectedProvider = provider
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(provider.rawValue)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(provider == .foundationModels ? "On-device, private" : "Cloud-based, requires API key")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if appState.selectedProvider == provider {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(ClarissaTheme.cyan)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .glassEffect(
                    appState.selectedProvider == provider
                        ? (reduceMotion ? .regular.tint(ClarissaTheme.purple.opacity(0.3)) : .regular.tint(ClarissaTheme.purple.opacity(0.3)).interactive())
                        : (reduceMotion ? .regular : .regular.interactive()),
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .glassEffectID(provider.id, in: settingsNamespace)
                .animation(.bouncy, value: appState.selectedProvider)
                .accessibilityLabel(provider.rawValue)
                .accessibilityHint(appState.selectedProvider == provider ? "Currently selected" : "Double-tap to select this provider")
                .accessibilityAddTraits(appState.selectedProvider == provider ? .isSelected : [])
            }
        }
    }

    private var legacyProviderPicker: some View {
        ForEach(LLMProviderType.allCases) { provider in
            Button {
                HapticManager.shared.selection()
                appState.selectedProvider = provider
            } label: {
                HStack {
                    VStack(alignment: .leading) {
                        Text(provider.rawValue)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(provider == .foundationModels ? "On-device, private" : "Cloud-based, requires API key")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if appState.selectedProvider == provider {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(ClarissaTheme.cyan)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(provider.rawValue)
            .accessibilityHint(appState.selectedProvider == provider ? "Currently selected" : "Double-tap to select this provider")
            .accessibilityAddTraits(appState.selectedProvider == provider ? .isSelected : [])
        }
    }

    private func formatModelName(_ model: String) -> String {
        let parts = model.split(separator: "/")
        if parts.count == 2 {
            return String(parts[1]).replacingOccurrences(of: "-", with: " ").capitalized
        }
        return model
    }
}

/// View for displaying and managing memories
struct MemoryListView: View {
    @Binding var memories: [Memory]

    var body: some View {
        List {
            if memories.isEmpty {
                Text("No memories stored yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(memories) { memory in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(memory.content)
                        Text(memory.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete(perform: deleteMemories)
            }
        }
        .navigationTitle("Memories")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func deleteMemories(at offsets: IndexSet) {
        for index in offsets {
            let memory = memories[index]
            Task {
                await MemoryManager.shared.remove(id: memory.id)
            }
        }
        memories.remove(atOffsets: offsets)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}

