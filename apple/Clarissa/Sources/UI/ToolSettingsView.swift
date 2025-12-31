import SwiftUI

/// Standalone view for managing tools - accessible from overflow menu
struct ToolSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var tools: [ToolInfo]
    @State private var enabledCount: Int
    @State private var isAtLimit: Bool
    let onDismiss: (() -> Void)?

    init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
        // Initialize state with current tool settings
        // This ensures tools are available immediately, not just after .task runs
        let settings = ToolSettings.shared
        _tools = State(initialValue: settings.allTools)
        _enabledCount = State(initialValue: settings.enabledCount)
        _isAtLimit = State(initialValue: settings.isAtFoundationModelsLimit)
    }

    private var isFoundationModels: Bool {
        appState.selectedProvider == .foundationModels
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
            // Header with title and done button
            HStack {
                Text("Tools")
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

            // Tools list
            List {
                Section {
                    ForEach(tools) { tool in
                        ToolRow(
                            tool: tool,
                            isAtLimit: isFoundationModels && isAtLimit,
                            onToggle: {
                                ToolSettings.shared.toggleTool(tool.id)
                                refreshTools()
                            }
                        )
                    }
                } header: {
                    if isFoundationModels {
                        Text("Enabled: \(enabledCount)/\(maxToolsForFoundationModels)")
                    } else {
                        Text("Built-in Tools")
                    }
                } footer: {
                    if isFoundationModels {
                        Text("Apple Intelligence works best with \(maxToolsForFoundationModels) or fewer tools.")
                    } else {
                        Text("Select which tools the assistant can use.")
                    }
                }

                Section {
                    customToolsComingSoon
                } header: {
                    Text("Custom Tools")
                }
            }
        }
        .frame(minWidth: 400, minHeight: 400)
    }
    #endif

    #if os(iOS)
    private var iOSContent: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(tools) { tool in
                        ToolRow(
                            tool: tool,
                            isAtLimit: isFoundationModels && isAtLimit,
                            onToggle: {
                                ToolSettings.shared.toggleTool(tool.id)
                                refreshTools()
                            }
                        )
                    }
                } header: {
                    if isFoundationModels {
                        Text("Enabled: \(enabledCount)/\(maxToolsForFoundationModels)")
                    } else {
                        Text("Built-in Tools")
                    }
                } footer: {
                    if isFoundationModels {
                        Text("Apple Intelligence works best with \(maxToolsForFoundationModels) or fewer tools.")
                    } else {
                        Text("Select which tools the assistant can use.")
                    }
                }

                Section {
                    customToolsComingSoon
                } header: {
                    Text("Custom Tools")
                }
            }
            .navigationTitle("Tools")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let onDismiss = onDismiss {
                    ToolbarItem(placement: .topBarTrailing) {
                        toolsDoneButton(onDismiss: onDismiss)
                    }
                }
            }
        }
        .tint(ClarissaTheme.purple)
        .task {
            refreshTools()
        }
    }
    #endif

    @MainActor
    private func refreshTools() {
        tools = ToolSettings.shared.allTools
        enabledCount = ToolSettings.shared.enabledCount
        isAtLimit = ToolSettings.shared.isAtFoundationModelsLimit
    }

    @ViewBuilder
    private func toolsDoneButton(onDismiss: @escaping () -> Void) -> some View {
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

    private var customToolsComingSoon: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.dashed")
                    .font(.title2)
                    .foregroundStyle(ClarissaTheme.purple.opacity(0.6))
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Add Custom Tool")
                        .foregroundStyle(.primary)
                    Text("Define your own tools with custom actions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption)
                Text("Coming Soon")
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(ClarissaTheme.purple)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(ClarissaTheme.purple.opacity(0.12))
            .clipShape(Capsule())
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Embedded Tools List (for Settings tab)

/// Embeddable version without NavigationStack for use inside Settings
struct EmbeddedToolsListView: View {
    let isFoundationModels: Bool

    @ObservedObject private var settings = ToolSettings.shared

    var body: some View {
        List {
            Section {
                ForEach(settings.allTools) { tool in
                    ToolRow(
                        tool: tool,
                        isAtLimit: isFoundationModels && settings.isAtFoundationModelsLimit,
                        onToggle: { settings.toggleTool(tool.id) }
                    )
                }
            } header: {
                if isFoundationModels {
                    Text("Enabled: \(settings.enabledCount)/\(maxToolsForFoundationModels)")
                } else {
                    Text("Built-in Tools")
                }
            } footer: {
                if isFoundationModels {
                    Text("Apple Intelligence works best with \(maxToolsForFoundationModels) or fewer tools.")
                } else {
                    Text("Select which tools the assistant can use.")
                }
            }
        }
        .navigationTitle("Tools")
    }
}

/// Row for a single tool toggle
private struct ToolRow: View {
    let tool: ToolInfo
    let isAtLimit: Bool
    let onToggle: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var canEnable: Bool {
        tool.isEnabled || !isAtLimit
    }

    var body: some View {
        Button {
            if canEnable {
                onToggle()
            }
        } label: {
            HStack(spacing: 12) {
                toolIcon

                VStack(alignment: .leading, spacing: 2) {
                    Text(tool.name)
                        .foregroundStyle(.primary)
                    Text(tool.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                toggleIndicator
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(canEnable ? 1.0 : 0.5)
        .animation(reduceMotion ? nil : .bouncy, value: tool.isEnabled)
    }

    /// Tool icon with solid background per Liquid Glass guide
    /// (glass should not be applied to content layer elements like List rows)
    private var toolIcon: some View {
        Image(systemName: tool.icon)
            .font(.title3)
            .foregroundStyle(tool.isEnabled ? ClarissaTheme.cyan : .secondary)
            .frame(width: 32, height: 32)
            .background(
                Circle()
                    .fill(tool.isEnabled ? ClarissaTheme.cyan.opacity(0.15) : Color.gray.opacity(0.1))
            )
    }

    @ViewBuilder
    private var toggleIndicator: some View {
        Image(systemName: tool.isEnabled ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(tool.isEnabled ? ClarissaTheme.cyan : Color.gray.opacity(0.3))
            .font(.title2)
    }
}

#Preview {
    ToolSettingsView()
        .environmentObject(AppState())
}

