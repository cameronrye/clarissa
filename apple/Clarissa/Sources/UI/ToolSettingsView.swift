import SwiftUI

/// View for configuring which tools are enabled
struct ToolSettingsView: View {
    @ObservedObject private var settings = ToolSettings.shared
    @EnvironmentObject var appState: AppState
    
    private var isFoundationModels: Bool {
        appState.selectedProvider == .foundationModels
    }
    
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
                    Text("Available Tools")
                }
            } footer: {
                if isFoundationModels {
                    Text("Apple Intelligence works best with \(maxToolsForFoundationModels) or fewer tools. Disable unused tools to improve reliability.")
                } else {
                    Text("Select which tools the assistant can use.")
                }
            }
        }
        .navigationTitle("Tools")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
    NavigationStack {
        ToolSettingsView()
            .environmentObject(AppState())
    }
}

