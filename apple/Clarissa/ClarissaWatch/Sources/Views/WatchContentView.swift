import SwiftUI
import WatchKit

/// Main content view for the Watch app
struct WatchContentView: View {
    @EnvironmentObject private var appState: WatchAppState
    @State private var showingVoiceInput = false
    @State private var showingHistory = false

    var body: some View {
        NavigationStack {
            Group {
                if appState.isReachable {
                    connectedView
                } else {
                    disconnectedView
                }
            }
            .navigationTitle("Clarissa")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingVoiceInput) {
                WatchVoiceInputView { text in
                    appState.sendQuery(text)
                }
            }
            .sheet(isPresented: $showingHistory) {
                ResponseHistoryView()
            }
        }
    }

    // MARK: - Connected State

    @ViewBuilder
    private var connectedView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Status indicator at top
                statusView
                    .padding(.top, 4)

                // Latest response or welcome message
                latestResponseView

                // Quick actions grid
                quickActionsView

                // Bottom action bar
                actionBar
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var latestResponseView: some View {
        if let latest = appState.responseHistory.first {
            VStack(alignment: .leading, spacing: 8) {
                // Query label
                Text(latest.query)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                // Response text
                Text(latest.response)
                    .font(.body)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Timestamp and history button
                HStack {
                    Text(latest.timestamp, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Spacer()

                    if appState.responseHistory.count > 1 {
                        Button {
                            showingHistory = true
                        } label: {
                            HStack(spacing: 2) {
                                Text("History")
                                Image(systemName: "chevron.right")
                            }
                            .font(.caption2)
                            .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(12)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(12)
        } else {
            // Welcome state - no history yet
            VStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.blue)

                Text("Ask me anything")
                    .font(.headline)

                Text("Use the mic or tap a quick action below")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 20)
        }
    }

    @ViewBuilder
    private var quickActionsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Actions")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(QuickAction.allCases) { action in
                    Button {
                        HapticManager.buttonTap()
                        appState.sendQuickAction(action)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: action.icon)
                                .font(.title3)
                            Text(action.shortLabel)
                                .font(.caption2)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .disabled(isProcessing)
                }
            }
        }
    }

    @ViewBuilder
    private var actionBar: some View {
        HStack(spacing: 12) {
            // Voice input button
            Button {
                HapticManager.buttonTap()
                showingVoiceInput = true
            } label: {
                HStack {
                    Image(systemName: "mic.fill")
                    Text("Ask")
                }
                .font(.body)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.blue)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .disabled(isProcessing)
            .accessibilityLabel("Ask Clarissa")
            .accessibilityHint("Opens voice input to ask a question")
        }
        .padding(.bottom, 8)
    }

    // MARK: - Disconnected State

    @ViewBuilder
    private var disconnectedView: some View {
        Spacer()

        VStack(spacing: 16) {
            // Connection status icon
            Image(systemName: "iphone.slash")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            // Explanation text
            VStack(spacing: 4) {
                Text("iPhone Required")
                    .font(.headline)

                Text("Open Clarissa on your iPhone to use the watch app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }

        Spacer()

        // Connection status indicator
        HStack(spacing: 6) {
            Circle()
                .fill(Color.orange)
                .frame(width: 8, height: 8)
            Text("Waiting for iPhone...")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Status View

    @ViewBuilder
    private var statusView: some View {
        switch appState.status {
        case .idle:
            EmptyView()

        case .listening:
            HStack(spacing: 4) {
                Image(systemName: "waveform")
                Text("Listening...")
            }
            .font(.caption)
            .foregroundStyle(.blue)

        case .sending:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Sending...")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

        case .waiting:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Waiting...")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

        case .processing(let message):
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.7)
                Text(message)
            }
            .font(.caption)
            .foregroundStyle(.orange)

        case .error(let message):
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(message)
            }
            .font(.caption)
            .foregroundStyle(.red)
            .onTapGesture {
                appState.clearError()
            }
        }
    }

    private var isProcessing: Bool {
        switch appState.status {
        case .idle, .error:
            return false
        default:
            return true
        }
    }
}

#Preview("Connected") {
    WatchContentView()
        .environmentObject({
            let state = WatchAppState()
            return state
        }())
}

#Preview("Disconnected") {
    WatchContentView()
        .environmentObject(WatchAppState())
}

