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
                                // Category badge
                                if let category = memory.category, category != .uncategorized {
                                    Text(category.rawValue.capitalized)
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(categoryColor(category).opacity(0.15))
                                        .foregroundStyle(categoryColor(category))
                                        .clipShape(Capsule())
                                }

                                // Confidence indicator
                                if let confidence = memory.confidence {
                                    HStack(spacing: 2) {
                                        Image(systemName: "brain")
                                            .font(.caption2)
                                        Text("\(Int(confidence * 100))%")
                                            .font(.caption2)
                                    }
                                    .foregroundStyle(confidenceColor(confidence))
                                }

                                // Relationship count
                                if let relationships = memory.relationships, !relationships.isEmpty {
                                    HStack(spacing: 2) {
                                        Image(systemName: "link")
                                            .font(.caption2)
                                        Text("\(relationships.count)")
                                            .font(.caption2)
                                    }
                                    .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(memory.createdAt, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if let topics = memory.topics, !topics.isEmpty {
                                Text(topics.joined(separator: ", "))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
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

    private func categoryColor(_ category: MemoryCategory) -> Color {
        switch category {
        case .fact: return .blue
        case .preference: return ClarissaTheme.purple
        case .routine: return .orange
        case .relationship: return .pink
        case .uncategorized: return .gray
        }
    }

    private func confidenceColor(_ confidence: Float) -> Color {
        if confidence >= 0.7 { return .green }
        if confidence >= 0.4 { return .orange }
        return .red
    }
}
