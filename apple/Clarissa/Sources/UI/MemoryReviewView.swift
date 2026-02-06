import SwiftUI

/// View for reviewing and cleaning up stale memories
/// Displays memories older than the configured threshold (default 30 days)
/// Accessible from Settings > Long-term Memory section
struct MemoryReviewView: View {
    @State private var staleMemories: [Memory] = []
    @State private var isLoading = true
    @State private var showMergeConfirmation = false
    @State private var mergeResult: String?

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("Loading memories...")
                        Spacer()
                    }
                }
            } else if staleMemories.isEmpty {
                Section {
                    ContentUnavailableView(
                        "All Memories Fresh",
                        systemImage: "checkmark.circle",
                        description: Text("No stale memories found. Memories older than \(ClarissaConstants.memoryStaleThresholdDays) days will appear here for review.")
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    Text("These memories are over \(ClarissaConstants.memoryStaleThresholdDays) days old. Review and remove any that are no longer relevant.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                } header: {
                    Text("\(staleMemories.count) Stale \(staleMemories.count == 1 ? "Memory" : "Memories")")
                }

                Section {
                    ForEach(staleMemories) { memory in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(memory.content)
                                .font(.body)

                            HStack(spacing: 8) {
                                Text(memory.createdAt, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                if let topics = memory.topics, !topics.isEmpty {
                                    Text(topics.joined(separator: ", "))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteMemory(memory)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            // Merge duplicates section
            Section {
                Button {
                    showMergeConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.merge")
                            .foregroundStyle(ClarissaTheme.purple)
                        Text("Merge Duplicate Memories")
                    }
                }

                if let result = mergeResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Cleanup")
            } footer: {
                Text("Finds and merges semantically similar memories to reduce clutter.")
            }
        }
        .navigationTitle("Review Memories")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            staleMemories = await MemoryManager.shared.getStaleMemories()
            isLoading = false
        }
        .confirmationDialog(
            "Merge Duplicates?",
            isPresented: $showMergeConfirmation,
            titleVisibility: .visible
        ) {
            Button("Merge") {
                Task {
                    let before = await MemoryManager.shared.getAll()
                    await MemoryManager.shared.mergeDuplicates()
                    let after = await MemoryManager.shared.getAll()
                    let removed = before.count - after.count
                    if removed > 0 {
                        mergeResult = "Merged \(removed) duplicate \(removed == 1 ? "memory" : "memories")"
                    } else {
                        mergeResult = "No duplicates found"
                    }
                    // Refresh stale list
                    staleMemories = await MemoryManager.shared.getStaleMemories()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will find and merge semantically similar memories. The most recent version will be kept.")
        }
    }

    private func deleteMemory(_ memory: Memory) {
        HapticManager.shared.warning()
        Task {
            await MemoryManager.shared.remove(id: memory.id)
            staleMemories.removeAll { $0.id == memory.id }
        }
    }
}
