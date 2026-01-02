import SwiftUI
import AVFoundation

#if os(macOS)
/// Tab options for macOS Settings
enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case tools = "Tools"
    case voice = "Voice"
    case shortcuts = "Shortcuts"
    case about = "About"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .tools: return "wrench.and.screwdriver"
        case .voice: return "speaker.wave.2"
        case .shortcuts: return "keyboard"
        case .about: return "info.circle"
        }
    }
}
#endif

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
    @State private var showingClearMemoriesConfirmation = false
    @State private var availableVoices: [AVSpeechSynthesisVoice] = []
    @State private var testSynthesizer: AVSpeechSynthesizer?
    @State private var isTestingVoice = false

    #if os(macOS)
    @State private var selectedTab: SettingsTab = .general
    #endif

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
        #if os(macOS)
        macOSSettingsView
            .tint(ClarissaTheme.purple)
            .task {
                await loadInitialData()
            }
        #else
        iOSSettingsView
            .tint(ClarissaTheme.purple)
            .task {
                await loadInitialData()
            }
        #endif
    }

    private func loadInitialData() async {
        memories = await MemoryManager.shared.getAll()
        openRouterApiKey = KeychainManager.shared.get(key: KeychainManager.Keys.openRouterApiKey) ?? ""
        loadAvailableVoices()
    }

    // MARK: - macOS Tabbed Settings

    #if os(macOS)
    private var macOSSettingsView: some View {
        TabView(selection: $selectedTab) {
            generalTabContent
                .tabItem {
                    Label(SettingsTab.general.rawValue, systemImage: SettingsTab.general.icon)
                }
                .tag(SettingsTab.general)

            toolsTabContent
                .tabItem {
                    Label(SettingsTab.tools.rawValue, systemImage: SettingsTab.tools.icon)
                }
                .tag(SettingsTab.tools)

            voiceTabContent
                .tabItem {
                    Label(SettingsTab.voice.rawValue, systemImage: SettingsTab.voice.icon)
                }
                .tag(SettingsTab.voice)

            shortcutsTabContent
                .tabItem {
                    Label(SettingsTab.shortcuts.rawValue, systemImage: SettingsTab.shortcuts.icon)
                }
                .tag(SettingsTab.shortcuts)

            aboutTabContent
                .tabItem {
                    Label(SettingsTab.about.rawValue, systemImage: SettingsTab.about.icon)
                }
                .tag(SettingsTab.about)
        }
        .frame(width: 500, height: 450)
    }

    private var generalTabContent: some View {
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
                    showingClearMemoriesConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Clear All Memories")
                    }
                }
                .confirmationDialog(
                    "Clear All Memories?",
                    isPresented: $showingClearMemoriesConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Clear All", role: .destructive) {
                        HapticManager.shared.warning()
                        Task {
                            await MemoryManager.shared.clear()
                            memories = []
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will permanently delete all saved memories. This action cannot be undone.")
                }
            } header: {
                Text("Long-term Memory")
            }
        }
        .formStyle(.grouped)
    }

    private var toolsTabContent: some View {
        ToolSettingsView()
            .environmentObject(appState)
    }

    private var voiceTabContent: some View {
        Form {
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
                            if isTestingVoice {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "play.circle")
                                    .foregroundStyle(ClarissaTheme.purple)
                            }
                            Text(isTestingVoice ? "Playing..." : "Test Voice")
                        }
                    }
                    .disabled(isTestingVoice)
                }
            } header: {
                Text("Voice Output")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("When enabled, Clarissa will speak responses aloud in voice mode.")
                    if voiceOutputEnabled {
                        Text("Premium and Enhanced voices provide the best quality. Download more in System Settings -> Accessibility -> Spoken Content -> System Voices.")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var shortcutsTabContent: some View {
        Form {
            Section {
                shortcutRow("New Conversation", shortcut: "Command+N")
                shortcutRow("Clear Conversation", shortcut: "Shift+Command+Delete")
                shortcutRow("Cancel Generation", shortcut: "Escape")
                shortcutRow("Settings", shortcut: "Command+,")
            } header: {
                Text("General")
            }

            Section {
                shortcutRow("Start Voice Input", shortcut: "Command+D")
                shortcutRow("Read Last Response", shortcut: "Shift+Command+R")
                shortcutRow("Stop Speaking", shortcut: "Command+.")
            } header: {
                Text("Voice")
            }
        }
        .formStyle(.grouped)
    }

    private func shortcutRow(_ action: String, shortcut: String) -> some View {
        HStack {
            Text(action)
            Spacer()
            Text(shortcut)
                .foregroundStyle(.secondary)
                .font(.system(.body, design: .monospaced))
        }
    }

    private var aboutTabContent: some View {
        Form {
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
                    Text(appVersion)
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
        .formStyle(.grouped)
    }
    #endif

    // MARK: - iOS Scrolling Settings

    #if os(iOS)
    private var iOSSettingsView: some View {
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
                                .textInputAutocapitalization(.never)
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
                        showingClearMemoriesConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Clear All Memories")
                        }
                    }
                    .confirmationDialog(
                        "Clear All Memories?",
                        isPresented: $showingClearMemoriesConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Clear All", role: .destructive) {
                            HapticManager.shared.warning()
                            Task {
                                await MemoryManager.shared.clear()
                                memories = []
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will permanently delete all saved memories. This action cannot be undone.")
                    }
                } header: {
                    Text("Long-term Memory")
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
                                if isTestingVoice {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "play.circle")
                                        .foregroundStyle(ClarissaTheme.purple)
                                }
                                Text(isTestingVoice ? "Playing..." : "Test Voice")
                            }
                        }
                        .disabled(isTestingVoice)
                    }
                } header: {
                    Text("Voice")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("When enabled, Clarissa will speak responses aloud in voice mode.")
                        if voiceOutputEnabled {
                            Text("Premium and Enhanced voices provide the best quality. Download more in Settings -> Accessibility -> Spoken Content -> Voices.")
                        }
                    }
                }

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
                        Text(appVersion)
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
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    #endif

    // MARK: - Version Helpers

    /// Display the app's marketing version and build number from the bundle.
    private var appVersion: String {
        let bundle = Bundle.main
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String
        switch (version, build) {
        case let (v?, b?):
            return "\(v) (\(b))"
        case let (v?, nil):
            return v
        case let (nil, b?):
            return b
        default:
            return "Unknown"
        }
    }

    // MARK: - Voice Helpers

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

    private func voiceDisplayName(for voice: AVSpeechSynthesisVoice) -> String {
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

    private var speechRateLabel: String {
        switch speechRate {
        case 0.0..<0.3: return "Slow"
        case 0.3..<0.6: return "Normal"
        case 0.6..<0.8: return "Fast"
        default: return "Very Fast"
        }
    }

    private func testVoice() {
        // Prevent multiple simultaneous tests
        guard !isTestingVoice else { return }
        isTestingVoice = true

        // Create and retain synthesizer to prevent deallocation during playback
        let synthesizer = AVSpeechSynthesizer()
        testSynthesizer = synthesizer

        let utterance = AVSpeechUtterance(string: "Hello, I'm Clarissa, your AI assistant.")
        utterance.rate = Float(speechRate) * AVSpeechUtteranceMaximumSpeechRate

        if !selectedVoiceIdentifier.isEmpty,
           let voice = AVSpeechSynthesisVoice(identifier: selectedVoiceIdentifier) {
            utterance.voice = voice
        }

        // Estimate duration based on text length and speech rate (rough approximation)
        // Average speaking rate is about 150 words per minute
        let wordCount = 7 // "Hello, I'm Clarissa, your AI assistant."
        let baseSeconds = Double(wordCount) / 2.5 // ~2.5 words per second at normal rate
        let adjustedSeconds = baseSeconds / max(0.1, speechRate * 2) // Adjust for rate
        let estimatedDuration = max(2.0, min(8.0, adjustedSeconds)) // Clamp between 2-8 seconds

        synthesizer.speak(utterance)

        // Reset the state after estimated playback duration
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(estimatedDuration * 1_000_000_000))
            isTestingVoice = false
        }
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
                .buttonStyle(.plain)
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
        // Provide haptic feedback for deletion
        HapticManager.shared.warning()

        for index in offsets {
            let memory = memories[index]
            Task {
                await MemoryManager.shared.remove(id: memory.id)
            }
        }
        memories.remove(atOffsets: offsets)
    }
}

/// Standalone view for managing memories - accessible from overflow menu
struct MemorySettingsView: View {
    @State private var memories: [Memory] = []
    @State private var showClearConfirmation = false
    let onDismiss: (() -> Void)?

    init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    var body: some View {
        #if os(macOS)
        macOSContent
        #else
        iOSContent
        #endif
    }

    #if os(macOS)
    private var macOSContent: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Memories")
                    .font(.headline)
                Spacer()
                if let onDismiss = onDismiss {
                    Button("Done") {
                        onDismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ClarissaTheme.purple)
                }
            }
            .padding()

            Divider()

            List {
                memorySection
                clearSection
            }
        }
        .frame(minWidth: 400, minHeight: 400)
        .task {
            await loadMemories()
        }
    }
    #endif

    #if os(iOS)
    private var iOSContent: some View {
        NavigationStack {
            List {
                memorySection
                clearSection
            }
            .navigationTitle("Memories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let onDismiss = onDismiss {
                    ToolbarItem(placement: .topBarTrailing) {
                        doneButton(onDismiss: onDismiss)
                    }
                }
            }
        }
        .tint(ClarissaTheme.purple)
        .task {
            await loadMemories()
        }
        .confirmationDialog(
            "Clear All Memories",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                Task {
                    await MemoryManager.shared.clear()
                    memories = []
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all stored memories. This action cannot be undone.")
        }
    }
    #endif

    @ViewBuilder
    private var memorySection: some View {
        Section {
            if memories.isEmpty {
                ContentUnavailableView(
                    "No Memories",
                    systemImage: "brain.head.profile",
                    description: Text("Clarissa will remember important information you share during conversations.")
                )
                .listRowBackground(Color.clear)
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
        } header: {
            if !memories.isEmpty {
                Text("\(memories.count) \(memories.count == 1 ? "Memory" : "Memories")")
            }
        } footer: {
            if !memories.isEmpty {
                Text("Swipe left on a memory to delete it.")
            }
        }
    }

    @ViewBuilder
    private var clearSection: some View {
        if !memories.isEmpty {
            Section {
                Button(role: .destructive) {
                    showClearConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Clear All Memories")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func doneButton(onDismiss: @escaping () -> Void) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            Button("Done") {
                onDismiss()
            }
            .buttonStyle(.glassProminent)
            .tint(ClarissaTheme.purple)
        } else {
            Button("Done") {
                onDismiss()
            }
            .foregroundStyle(ClarissaTheme.purple)
        }
    }

    private func loadMemories() async {
        memories = await MemoryManager.shared.getAll()
    }

    private func deleteMemories(at offsets: IndexSet) {
        HapticManager.shared.warning()

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

