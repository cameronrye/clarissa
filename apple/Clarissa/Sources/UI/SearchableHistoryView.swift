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
    @State private var selectedDateFilter: DateFilter = .all
    @State private var selectedTopics: Set<String> = []
    @State private var availableTopics: [String] = []
    @State private var currentSessionId: UUID?
    @State private var isLoading = true
    @State private var editingSessionId: UUID?
    @State private var editingTitle: String = ""

    private var filteredSessions: [Session] {
        var result = sessions

        // Full-text search
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { session in
                session.title.lowercased().contains(query) ||
                session.messages.contains(where: { $0.content.lowercased().contains(query) }) ||
                (session.topics?.contains(where: { $0.lowercased().contains(query) }) ?? false)
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

        // Topic filter
        if !selectedTopics.isEmpty {
            result = result.filter { session in
                guard let sessionTopics = session.topics else { return false }
                return !selectedTopics.isDisjoint(with: Set(sessionTopics))
            }
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
                    ContentUnavailableView.search(text: searchText)
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
            // Date filter
            Picker("Date", selection: $selectedDateFilter) {
                ForEach(DateFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            // Topic chips
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
                        TextField("Title", text: $editingTitle, onCommit: {
                            Task {
                                await viewModel.renameSession(id: session.id, newTitle: editingTitle)
                                editingSessionId = nil
                                await loadData()
                            }
                        })
                        .textFieldStyle(.roundedBorder)
                        .font(.headline)
                    } else {
                        Text(session.title)
                            .font(.headline)
                            .lineLimit(1)
                    }

                    Spacer()

                    if session.id == currentSessionId {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(ClarissaTheme.purple)
                            .font(.caption)
                    }
                }

                // Preview of last user message
                if let lastUser = session.messages.last(where: { $0.role == .user }) {
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

                    // Topic tags
                    if let topics = session.topics, !topics.isEmpty {
                        Text(topics.prefix(2).joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading) {
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
    }

    // MARK: - Data

    private func loadData() async {
        sessions = await viewModel.getAllSessions()
        currentSessionId = await viewModel.getCurrentSessionId()
        availableTopics = await SessionManager.shared.getAllTopics()
        isLoading = false
    }

    private func deleteSessions(at offsets: IndexSet) {
        let sessionsToDelete = offsets.map { filteredSessions[$0] }
        for session in sessionsToDelete {
            Task {
                await viewModel.deleteSession(id: session.id)
                await loadData()
            }
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
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
