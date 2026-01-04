import SwiftUI

/// View showing response history on the watch
struct ResponseHistoryView: View {
    @EnvironmentObject private var appState: WatchAppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if appState.responseHistory.isEmpty {
                    emptyState
                } else {
                    historyList
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("No History")
                .font(.headline)

            Text("Your recent queries will appear here")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    @ViewBuilder
    private var historyList: some View {
        List {
            ForEach(appState.responseHistory) { item in
                NavigationLink {
                    ResponseDetailView(item: item)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.query)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Text(item.response)
                            .font(.body)
                            .lineLimit(2)

                        Text(item.timestamp, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
            }

            // Clear history button
            Section {
                Button(role: .destructive) {
                    HapticManager.buttonTap()
                    appState.clearHistory()
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Clear History")
                    }
                }
            }
        }
    }
}

/// Detail view for a single response
struct ResponseDetailView: View {
    let item: ResponseHistoryItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Query
                VStack(alignment: .leading, spacing: 4) {
                    Text("Question")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(item.query)
                        .font(.body)
                }

                Divider()

                // Response
                VStack(alignment: .leading, spacing: 4) {
                    Text("Answer")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(item.response)
                        .font(.body)
                }

                Divider()

                // Timestamp
                Text(item.timestamp, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding()
        }
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    ResponseHistoryView()
        .environmentObject(WatchAppState())
}

