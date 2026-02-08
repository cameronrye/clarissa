import SwiftUI

/// Shows the planned tool chain steps before execution and lets users approve, edit, or skip steps.
struct ChainPreviewView: View {
    let chain: ToolChain
    let onApprove: (Set<UUID>) -> Void  // Set of skipped step IDs
    let onCancel: () -> Void

    @State private var skippedSteps: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: chain.icon)
                    .font(.title3)
                    .foregroundStyle(ClarissaTheme.gradient)
                VStack(alignment: .leading, spacing: 2) {
                    Text(chain.name)
                        .font(.headline)
                    Text(chain.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.bottom, 4)

            // Step list
            ForEach(Array(chain.steps.enumerated()), id: \.element.id) { index, step in
                ChainStepRow(
                    index: index,
                    step: step,
                    isSkipped: skippedSteps.contains(step.id),
                    onToggleSkip: {
                        if step.isOptional {
                            if skippedSteps.contains(step.id) {
                                skippedSteps.remove(step.id)
                            } else {
                                skippedSteps.insert(step.id)
                            }
                        }
                    }
                )
            }

            // Action buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    onApprove(skippedSteps)
                } label: {
                    Label("Run Chain", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(ClarissaTheme.purple)
            }
            .padding(.top, 8)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// A single step row in the chain preview
private struct ChainStepRow: View {
    let index: Int
    let step: ToolChainStep
    let isSkipped: Bool
    let onToggleSkip: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Step number
            ZStack {
                Circle()
                    .fill(isSkipped ? Color.secondary.opacity(0.3) : ClarissaTheme.purple.opacity(0.15))
                    .frame(width: 28, height: 28)
                Text("\(index + 1)")
                    .font(.caption.bold())
                    .foregroundStyle(isSkipped ? .secondary : ClarissaTheme.purple)
            }

            // Step info
            VStack(alignment: .leading, spacing: 2) {
                Text(step.label)
                    .font(.subheadline)
                    .strikethrough(isSkipped)
                    .foregroundStyle(isSkipped ? .secondary : .primary)

                Text(ToolDisplayNames.format(step.toolName))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Optional badge / skip toggle
            if step.isOptional {
                Button {
                    onToggleSkip()
                } label: {
                    Image(systemName: isSkipped ? "arrow.uturn.backward" : "forward.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSkipped ? "Include step" : "Skip step")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if step.isOptional { onToggleSkip() }
        }
    }
}

// MARK: - Chain Execution Progress View

/// Shows real-time progress during chain execution
struct ChainProgressView: View {
    let chain: ToolChain
    let stepStatuses: [UUID: ChainStepStatus]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: chain.icon)
                    .foregroundStyle(ClarissaTheme.gradient)
                Text(chain.name)
                    .font(.headline)
                Spacer()
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            ForEach(Array(chain.steps.enumerated()), id: \.element.id) { index, step in
                HStack(spacing: 8) {
                    statusIcon(for: step.id)
                        .frame(width: 20, height: 20)

                    Text(step.label)
                        .font(.caption)
                        .foregroundStyle(foregroundColor(for: step.id))

                    Spacer()
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var isRunning: Bool {
        stepStatuses.values.contains { if case .running = $0 { return true }; return false }
    }

    @ViewBuilder
    private func statusIcon(for stepId: UUID) -> some View {
        let status = stepStatuses[stepId]
        switch status {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .running:
            ProgressView()
                .controlSize(.mini)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .skipped:
            Image(systemName: "forward.circle.fill")
                .foregroundStyle(.secondary)
        case .pending, .none:
            Image(systemName: "circle")
                .foregroundStyle(.secondary.opacity(0.5))
        }
    }

    private func foregroundColor(for stepId: UUID) -> Color {
        let status = stepStatuses[stepId]
        switch status {
        case .completed: return .primary
        case .running: return .primary
        case .failed: return .red
        case .skipped: return .secondary
        case .pending, .none: return .secondary
        }
    }
}

// MARK: - Tool Chain Picker

/// Grid picker for selecting a tool chain to run
struct ToolChainPicker: View {
    let chains: [ToolChain]
    let onSelect: (ToolChain) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(chains) { chain in
                Button {
                    onSelect(chain)
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: chain.icon)
                            .font(.title2)
                            .foregroundStyle(ClarissaTheme.gradient)

                        Text(chain.name)
                            .font(.caption.bold())
                            .lineLimit(1)

                        Text("\(chain.steps.count) steps")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
