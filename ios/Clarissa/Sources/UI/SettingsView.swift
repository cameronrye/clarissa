import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @AppStorage("selectedModel") private var selectedModel: String = "anthropic/claude-sonnet-4"
    @AppStorage("autoApproveTools") private var autoApproveTools: Bool = false

    @State private var openRouterApiKey: String = ""
    @State private var showingApiKey = false
    @State private var memories: [Memory] = []
    @State private var showMemories = false
    @State private var showingSaveConfirmation = false

    var onProviderChange: (() -> Void)?

    private let availableModels = [
        "anthropic/claude-sonnet-4",
        "anthropic/claude-opus-4",
        "openai/gpt-4o",
        "openai/gpt-4o-mini",
        "google/gemini-2.0-flash",
        "meta-llama/llama-3.3-70b-instruct"
    ]

    var body: some View {
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
                    Toggle("Auto-approve Tools", isOn: $autoApproveTools)
                } header: {
                    Text("Tools")
                } footer: {
                    Text("When enabled, tools like Calendar will execute without asking for confirmation.")
                }

                Section {
                    NavigationLink {
                        MemoryListView(memories: $memories)
                    } label: {
                        HStack {
                            Text("Memories")
                            Spacer()
                            Text("\(memories.count)")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button("Clear All Memories", role: .destructive) {
                        Task {
                            await MemoryManager.shared.clear()
                            memories = []
                        }
                    }
                } header: {
                    Text("Long-term Memory")
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        onProviderChange?()
                        dismiss()
                    }
                    .foregroundStyle(ClarissaTheme.purple)
                }
            }
            #else
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onProviderChange?()
                        dismiss()
                    }
                    .foregroundStyle(ClarissaTheme.purple)
                }
            }
            #endif
        }
        .tint(ClarissaTheme.purple)
        .task {
            memories = await MemoryManager.shared.getAll()
            // Load API key from Keychain
            openRouterApiKey = KeychainManager.shared.get(key: KeychainManager.Keys.openRouterApiKey) ?? ""
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
        ForEach(LLMProviderType.allCases) { provider in
            Button {
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

