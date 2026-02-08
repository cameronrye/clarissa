import SwiftUI

/// Date range filter options for conversation history
enum DateFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case today = "Today"
    case week = "This Week"
    case month = "This Month"

    var id: String { rawValue }
}

/// Searchable, filterable conversation history view
/// Supports full-text search, date range filters, and topic chips
struct SearchableHistoryView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var sessions: [Session] = []
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var selectedDateFilter: DateFilter = .all
    @State private var selectedTopics: Set<String> = []
    @State private var availableTopics: [String] = []
    @State private var currentSessionId: UUID?
    @State private var isLoading = true
    @State private var editingSessionId: UUID?
    @State private var editingTitle: String = ""
    @State private var showFavoritesOnly = false
    @State private var addingTagSessionId: UUID?
    @State private var newTagText = ""

    private var filteredSessions: [Session] {
        var result = sessions

        // Favorites filter
        if showFavoritesOnly {
            result = result.filter { $0.isFavorite == true }
        }

        // Full-text search across title, messages, summary, topics, and manual tags
        if !debouncedSearchText.isEmpty {
            let query = debouncedSearchText.lowercased()
            result = result.filter { session in
                session.title.lowercased().contains(query) ||
                session.summary?.lowercased().contains(query) == true ||
                session.messages.contains(where: { $0.content.lowercased().contains(query) }) ||
                (session.topics?.contains(where: { $0.lowercased().contains(query) }) ?? false) ||
                (session.manualTags?.contains(where: { $0.lowercased().contains(query) }) ?? false)
            }
        }

        // Date filter
        let now = Date()
        switch selectedDateFilter {
        case .all:
            break
        case .today:
            result = result.filter { Calendar.current.isDateInToday($0.updatedAt) }
        case .week:
            if let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now) {
                result = result.filter { $0.updatedAt >= weekAgo }
            }
        case .month:
            if let monthAgo = Calendar.current.date(byAdding: .month, value: -1, to: now) {
                result = result.filter { $0.updatedAt >= monthAgo }
            }
        }

        // Topic/tag filter
        if !selectedTopics.isEmpty {
            result = result.filter { session in
                let allTags = Set(session.allTags)
                return !selectedTopics.isDisjoint(with: allTags)
            }
        }

        // Sort: favorites first, then by updatedAt
        result.sort { lhs, rhs in
            let lhsFav = lhs.isFavorite == true
            let rhsFav = rhs.isFavorite == true
            if lhsFav != rhsFav { return lhsFav }
            return lhs.updatedAt > rhs.updatedAt
        }

        return result
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter bar
                if !sessions.isEmpty {
                    filterBar
                }

                // Session list
                if isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if filteredSessions.isEmpty {
                    ContentUnavailableView.search(text: debouncedSearchText)
                } else {
                    sessionList
                }
            }
            .navigationTitle("History")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search conversations")
            .onChange(of: searchText) { _, newValue in
                searchDebounceTask?.cancel()
                searchDebounceTask = Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    debouncedSearchText = newValue
                }
            }
            .task {
                await loadData()
            }
            .onChange(of: viewModel.sessionVersion) { _, _ in
                Task { await loadData() }
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        VStack(spacing: 8) {
            HStack {
                // Date filter
                Picker("Date", selection: $selectedDateFilter) {
                    ForEach(DateFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)

                // Favorites toggle
                Button {
                    showFavoritesOnly.toggle()
                } label: {
                    Image(systemName: showFavoritesOnly ? "star.fill" : "star")
                        .foregroundStyle(showFavoritesOnly ? .yellow : .secondary)
                        .font(.body)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showFavoritesOnly ? "Show all conversations" : "Show favorites only")
                .accessibilityHint("Double-tap to toggle favorites filter")
            }
            .padding(.horizontal)

            // Topic/tag chips
            if !availableTopics.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(availableTopics, id: \.self) { topic in
                            TopicChipView(
                                topic: topic,
                                isSelected: selectedTopics.contains(topic)
                            ) {
                                if selectedTopics.contains(topic) {
                                    selectedTopics.remove(topic)
                                } else {
                                    selectedTopics.insert(topic)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Session List

    private var sessionList: some View {
        List {
            ForEach(filteredSessions) { session in
                sessionRow(session)
            }
            .onDelete(perform: deleteSessions)
        }
        .listStyle(.plain)
    }

    private func sessionRow(_ session: Session) -> some View {
        Button {
            Task {
                await viewModel.switchToSession(id: session.id)
                dismiss()
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    if editingSessionId == session.id {
                        TextField("Title", text: $editingTitle)
                        .onSubmit {
                            Task {
                                await viewModel.renameSession(id: session.id, newTitle: editingTitle)
                                editingSessionId = nil
                                await loadData()
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        .font(.headline)
                    } else {
                        Text(session.title)
                            .font(.headline)
                            .lineLimit(1)
                    }

                    Spacer()

                    if session.isFavorite == true {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                            .accessibilityLabel("Favorited")
                    }

                    if session.id == currentSessionId {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(ClarissaTheme.purple)
                            .font(.caption)
                    }
                }

                // Show summary if available, otherwise last user message
                if let summary = session.summary {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let lastUser = session.messages.last(where: { $0.role == .user }) {
                    Text(lastUser.content)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    // Relative time
                    Text(session.updatedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    // Message count
                    let userCount = session.messages.filter { $0.role == .user }.count
                    Text("\(userCount) \(userCount == 1 ? "message" : "messages")")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    // Tags (auto topics + manual)
                    let tags = session.allTags
                    if !tags.isEmpty {
                        Text(tags.prefix(2).joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .accessibilityHint(session.id == currentSessionId ? "Current conversation" : "Double-tap to open this conversation")
        .swipeActions(edge: .leading) {
            Button {
                Task {
                    await SessionManager.shared.toggleFavorite(id: session.id)
                    await loadData()
                }
            } label: {
                Label(
                    session.isFavorite == true ? "Unfavorite" : "Favorite",
                    systemImage: session.isFavorite == true ? "star.slash" : "star"
                )
            }
            .tint(.yellow)

            Button {
                editingTitle = session.title
                editingSessionId = session.id
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(ClarissaTheme.purple)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                Task {
                    await viewModel.deleteSession(id: session.id)
                    await loadData()
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button {
                Task {
                    await SessionManager.shared.toggleFavorite(id: session.id)
                    await loadData()
                }
            } label: {
                Label(
                    session.isFavorite == true ? "Unfavorite" : "Favorite",
                    systemImage: session.isFavorite == true ? "star.slash.fill" : "star"
                )
            }

            Button {
                addingTagSessionId = session.id
                newTagText = ""
            } label: {
                Label("Add Tag", systemImage: "tag")
            }

            Button {
                editingTitle = session.title
                editingSessionId = session.id
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Button(role: .destructive) {
                Task {
                    await viewModel.deleteSession(id: session.id)
                    await loadData()
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .alert("Add Tag", isPresented: Binding(
            get: { addingTagSessionId == session.id },
            set: { if !$0 { addingTagSessionId = nil } }
        )) {
            TextField("Tag name", text: $newTagText)
            Button("Add") {
                Task {
                    if let id = addingTagSessionId {
                        await SessionManager.shared.addTag(newTagText, to: id)
                        addingTagSessionId = nil
                        await loadData()
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                addingTagSessionId = nil
            }
        }
    }

    // MARK: - Data

    private func loadData() async {
        sessions = await viewModel.getAllSessions()
        currentSessionId = await viewModel.getCurrentSessionId()
        availableTopics = await SessionManager.shared.getAllTags()
        isLoading = false
    }

    private func deleteSessions(at offsets: IndexSet) {
        let sessionsToDelete = offsets.map { filteredSessions[$0] }
        Task {
            for session in sessionsToDelete {
                await viewModel.deleteSession(id: session.id)
            }
            await loadData()
        }
    }
}

// MARK: - Topic Chip

/// A selectable chip for topic filtering
struct TopicChipView: View {
    let topic: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(topic)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? AnyShapeStyle(ClarissaTheme.gradient) : AnyShapeStyle(Color.secondary.opacity(0.15)))
                )
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(topic) filter")
        .accessibilityHint(isSelected ? "Double-tap to remove this filter" : "Double-tap to filter by this topic")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
