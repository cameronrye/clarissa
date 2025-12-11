import SwiftUI
#if os(iOS)
import UIKit
#endif

struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    @FocusState private var isInputFocused: Bool

    #if os(iOS)
    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
    private let notificationFeedback = UINotificationFeedbackGenerator()
    #endif

    var body: some View {
        VStack(spacing: 0) {
            // Provider setup loading state
            if viewModel.isSettingUpProvider {
                Spacer()
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(ClarissaTheme.purple)
                    Text("Setting up...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else if viewModel.messages.isEmpty && viewModel.streamingContent.isEmpty && !viewModel.isLoading {
                // Empty state with suggestions
                EmptyStateView(onSuggestionTap: { suggestion in
                    viewModel.inputText = suggestion
                    viewModel.sendMessage()
                })
            } else {
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(
                                message: message,
                                onRetry: message.role == .assistant ? { viewModel.retryLastMessage() } : nil
                            )
                            .id(message.id)
                            .transition(.asymmetric(
                                insertion: .move(edge: message.role == .user ? .trailing : .leading)
                                    .combined(with: .opacity),
                                removal: .opacity
                            ))
                        }
                        .animation(.easeOut(duration: 0.25), value: viewModel.messages.count)
                        
                        // Streaming content with typing indicator
                        if !viewModel.streamingContent.isEmpty {
                            StreamingMessageBubble(content: viewModel.streamingContent)
                                .id("streaming")
                        }
                        
                        // Loading indicator with cancel button
                        if viewModel.isLoading && viewModel.streamingContent.isEmpty {
                            HStack {
                                ProgressView()
                                    .tint(ClarissaTheme.purple)
                                    .padding(.horizontal)
                                Text("Thinking...")
                                    .foregroundStyle(ClarissaTheme.purple)

                                Spacer()

                                if viewModel.canCancel {
                                    Button {
                                        triggerHaptic()
                                        viewModel.cancelGeneration()
                                    } label: {
                                        Image(systemName: "stop.circle.fill")
                                            .foregroundStyle(ClarissaTheme.pink)
                                    }
                                }
                            }
                            .padding()
                            .id("loading")
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    withAnimation {
                        if let lastId = viewModel.messages.last?.id {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: viewModel.streamingContent) { _, _ in
                    withAnimation {
                        proxy.scrollTo("streaming", anchor: .bottom)
                    }
                }
            }
            
            Divider()
            
            // Voice mode indicator
            if viewModel.isVoiceModeActive {
                VoiceModeIndicator(
                    isListening: viewModel.isRecording,
                    isSpeaking: viewModel.isSpeaking,
                    onExit: {
                        triggerHaptic()
                        Task { await viewModel.toggleVoiceMode() }
                    }
                )
            }

            // Input area
            HStack(spacing: 12) {
                // Voice input button
                Button {
                    triggerHaptic()
                    Task { await viewModel.toggleVoiceInput() }
                } label: {
                    ZStack {
                        if viewModel.isRecording {
                            // Animated recording indicator
                            Circle()
                                .fill(Color.red.opacity(0.2))
                                .frame(width: 36, height: 36)

                            Image(systemName: "waveform")
                                .font(.title3)
                                .foregroundStyle(.red)
                                .symbolEffect(.variableColor.iterative, options: .repeating)
                        } else {
                            Image(systemName: "mic.circle.fill")
                                .font(.title2)
                                .foregroundStyle(ClarissaTheme.gradient)
                        }
                    }
                }
                .accessibilityLabel(viewModel.isRecording ? "Stop recording" : "Start voice input")
                .accessibilityHint(viewModel.isRecording ? "Tap to stop recording and use transcribed text" : "Tap to speak your message")

                TextField("Message Clarissa...", text: $viewModel.inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .focused($isInputFocused)
                    .onSubmit {
                        triggerHaptic()
                        viewModel.sendMessage()
                    }
                    .accessibilityLabel("Message input")
                    .accessibilityHint("Type your message to Clarissa")

                let isDisabled = viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading

                // Stop speaking button (when assistant is speaking)
                if viewModel.isSpeaking {
                    Button {
                        triggerHaptic()
                        viewModel.stopSpeaking()
                    } label: {
                        Image(systemName: "speaker.slash.circle.fill")
                            .font(.title2)
                            .foregroundStyle(ClarissaTheme.pink)
                    }
                    .accessibilityLabel("Stop speaking")
                    .accessibilityHint("Stop Clarissa from speaking")
                }

                Button {
                    triggerHaptic()
                    viewModel.sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(isDisabled ? AnyShapeStyle(Color.secondary) : AnyShapeStyle(ClarissaTheme.gradient))
                }
                .disabled(isDisabled)
                .accessibilityLabel("Send message")
                .accessibilityHint(isDisabled ? "Enter a message first" : "Send your message")
            }
            .padding()
            .background(.bar)
            } // end else (provider ready)
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .sheet(item: $viewModel.pendingToolConfirmation) { confirmation in
            ToolConfirmationSheet(
                confirmation: confirmation,
                onConfirm: { viewModel.confirmTool(true) },
                onCancel: { viewModel.confirmTool(false) }
            )
            .presentationDetents([.medium])
        }
        #if os(macOS)
        // Keyboard shortcuts for Mac
        .keyboardShortcut(.return, modifiers: .command) // Cmd+Return to send
        #endif
    }

    private func triggerHaptic() {
        #if os(iOS)
        impactFeedback.impactOccurred()
        #endif
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    var onRetry: (() -> Void)? = nil

    @State private var showCopied = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// Max width for message bubbles on larger screens (iPad/Mac)
    private var maxBubbleWidth: CGFloat? {
        horizontalSizeClass == .regular ? 600 : nil
    }

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if message.role == .tool {
                    ToolStatusView(message: message, onRetry: message.toolStatus == .failed ? onRetry : nil)
                        .accessibilityLabel(toolAccessibilityLabel)
                } else if message.role == .user {
                    messageContent
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(ClarissaTheme.userBubbleGradient)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .frame(maxWidth: maxBubbleWidth, alignment: .trailing)
                        .contextMenu {
                            copyButton
                        }
                        .accessibilityLabel("You said: \(message.content)")
                } else {
                    messageContent
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(ClarissaTheme.assistantBubble)
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .frame(maxWidth: maxBubbleWidth, alignment: .leading)
                        .contextMenu {
                            copyButton
                            if let onRetry = onRetry {
                                Button {
                                    onRetry()
                                } label: {
                                    Label("Retry", systemImage: "arrow.clockwise")
                                }
                            }
                        }
                        .accessibilityLabel("Clarissa said: \(message.content)")
                }

                // Show copied confirmation
                if showCopied {
                    Text("Copied!")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }

            if message.role != .user {
                Spacer(minLength: 60)
            }
        }
    }

    private var copyButton: some View {
        Button {
            copyToClipboard()
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
    }

    private func copyToClipboard() {
        #if os(iOS)
        UIPasteboard.general.string = message.content
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
        #endif

        withAnimation {
            showCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCopied = false
            }
        }
    }

    @ViewBuilder
    private var messageContent: some View {
        if message.role == .assistant {
            // Render Markdown for assistant messages
            Text(markdownAttributedString)
        } else {
            // Plain text for user messages
            Text(message.content)
        }
    }

    private var markdownAttributedString: AttributedString {
        do {
            return try AttributedString(markdown: message.content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        } catch {
            return AttributedString(message.content)
        }
    }

    private var toolAccessibilityLabel: String {
        let status: String
        switch message.toolStatus {
        case .running:
            status = "running"
        case .completed:
            status = "completed"
        case .failed:
            status = "failed"
        case .none:
            status = ""
        }
        return "Tool \(message.content) \(status)"
    }
}

/// Message bubble with pulsing cursor for streaming content
struct StreamingMessageBubble: View {
    let content: String
    @State private var cursorVisible = true
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var maxBubbleWidth: CGFloat? {
        horizontalSizeClass == .regular ? 600 : nil
    }

    var body: some View {
        HStack {
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text(content)
                    .textSelection(.enabled)

                // Pulsing cursor
                Text("|")
                    .fontWeight(.light)
                    .opacity(cursorVisible ? 1 : 0)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: cursorVisible)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(ClarissaTheme.assistantBubble)
            .foregroundStyle(.primary)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .frame(maxWidth: maxBubbleWidth, alignment: .leading)

            Spacer(minLength: 60)
        }
        .onAppear {
            cursorVisible = false
        }
    }
}

/// Empty state view with logo and suggested prompts
struct EmptyStateView: View {
    let onSuggestionTap: (String) -> Void

    private let suggestions = [
        "What's the weather like today?",
        "Set a reminder for tomorrow at 9am",
        "What can you help me with?",
        "Tell me a fun fact"
    ]

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Logo
            VStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 48))
                    .foregroundStyle(ClarissaTheme.gradient)

                Text("Clarissa")
                    .font(.title.bold())
                    .gradientForeground()

                Text("Your AI assistant")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Suggested prompts
            VStack(alignment: .leading, spacing: 8) {
                Text("Try asking:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        onSuggestionTap(suggestion)
                    } label: {
                        HStack {
                            Text(suggestion)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.circle.fill")
                                .foregroundStyle(ClarissaTheme.gradient)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(ClarissaTheme.assistantBubble)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: 500)
    }
}

/// View for displaying tool execution status
struct ToolStatusView: View {
    let message: ChatMessage
    var onRetry: (() -> Void)? = nil

    /// Color based on tool status: yellow for running, green for completed, red for failed
    private var statusColor: Color {
        switch message.toolStatus {
        case .running:
            return .yellow
        case .completed:
            return .green
        case .failed:
            return .red
        case .none:
            return ClarissaTheme.cyan
        }
    }

    /// Background color with appropriate opacity
    private var backgroundColor: Color {
        statusColor.opacity(0.15)
    }

    var body: some View {
        HStack(spacing: 8) {
            if message.toolStatus == .running {
                ProgressView()
                    .controlSize(.small)
                    .tint(statusColor)
            } else {
                Image(systemName: message.toolStatus == .completed ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(statusColor)
            }

            Text(message.content)
                .font(.subheadline)

            // Retry button for failed tools
            if message.toolStatus == .failed, let onRetry = onRetry {
                Button {
                    onRetry()
                } label: {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .foregroundStyle(ClarissaTheme.purple)
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct ToolConfirmationSheet: View {
    let confirmation: ToolConfirmation
    let onConfirm: () -> Void
    let onCancel: () -> Void

    #if os(iOS)
    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
    private let notificationFeedback = UINotificationFeedbackGenerator()
    #endif

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.largeTitle)
                    .foregroundStyle(ClarissaTheme.gradient)

                Text("Tool Confirmation")
                    .font(.title2.bold())
                    .gradientForeground()

                Text("Clarissa wants to use the **\(confirmation.name)** tool")
                    .multilineTextAlignment(.center)

                GroupBox {
                    ScrollView {
                        Text(formatArguments(confirmation.arguments))
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 150)
                }

                Spacer()

                HStack(spacing: 16) {
                    Button("Deny", role: .cancel) {
                        triggerDenyHaptic()
                        onCancel()
                    }
                    .buttonStyle(.bordered)
                    .tint(ClarissaTheme.pink)

                    Button("Allow") {
                        triggerAllowHaptic()
                        onConfirm()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ClarissaTheme.purple)
                }
            }
            .padding()
            .onAppear {
                triggerAppearHaptic()
            }
        }
        .tint(ClarissaTheme.purple)
    }

    private func triggerAppearHaptic() {
        #if os(iOS)
        notificationFeedback.notificationOccurred(.warning)
        #endif
    }

    private func triggerAllowHaptic() {
        #if os(iOS)
        notificationFeedback.notificationOccurred(.success)
        #endif
    }

    private func triggerDenyHaptic() {
        #if os(iOS)
        impactFeedback.impactOccurred()
        #endif
    }
    
    private func formatArguments(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: .prettyPrinted),
              let string = String(data: pretty, encoding: .utf8) else {
            return json
        }
        return string
    }
}

/// View for browsing and switching between past sessions
struct SessionHistoryView: View {
    @ObservedObject var viewModel: ChatViewModel
    let onDismiss: () -> Void
    @State private var sessions: [Session] = []
    @State private var currentSessionId: UUID?

    var body: some View {
        NavigationStack {
            List {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "No History",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Your conversations will appear here.")
                    )
                } else {
                    ForEach(sessions) { session in
                        SessionRowView(
                            session: session,
                            isCurrentSession: session.id == currentSessionId,
                            onTap: {
                                Task {
                                    await viewModel.switchToSession(id: session.id)
                                    onDismiss()
                                }
                            }
                        )
                    }
                    .onDelete(perform: deleteSessions)
                }
            }
            .navigationTitle("History")
            .refreshable {
                await loadData()
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        onDismiss()
                    }
                    .foregroundStyle(ClarissaTheme.purple)
                }
            }
            #else
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDismiss()
                    }
                    .foregroundStyle(ClarissaTheme.purple)
                }
            }
            #endif
        }
        .tint(ClarissaTheme.purple)
        .task {
            await loadData()
        }
    }

    private func loadData() async {
        sessions = await viewModel.getAllSessions()
        currentSessionId = await viewModel.getCurrentSessionId()
    }

    private func deleteSessions(at offsets: IndexSet) {
        for index in offsets {
            let session = sessions[index]
            Task {
                await viewModel.deleteSession(id: session.id)
            }
        }
        sessions.remove(atOffsets: offsets)
    }
}

/// Row view for a single session in history
struct SessionRowView: View {
    let session: Session
    let isCurrentSession: Bool
    let onTap: () -> Void

    /// Get a preview of the last user message
    private var messagePreview: String? {
        session.messages.last(where: { $0.role == .user })?.content
    }

    /// Format relative time (e.g., "2 hours ago", "Yesterday")
    private var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: session.updatedAt, relativeTo: Date())
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(session.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if isCurrentSession {
                            Text("Current")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(ClarissaTheme.purple)
                                .clipShape(Capsule())
                        }
                    }

                    // Message preview
                    if let preview = messagePreview {
                        Text(preview)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "message")
                            .font(.caption2)
                        Text("\(session.messages.count)")
                        Text("•")
                        Text(relativeTime)
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
    }
}

/// Indicator shown when voice mode is active
struct VoiceModeIndicator: View {
    let isListening: Bool
    let isSpeaking: Bool
    let onExit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            HStack(spacing: 8) {
                if isListening {
                    Image(systemName: "waveform")
                        .foregroundStyle(.red)
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                    Text("Listening...")
                        .foregroundStyle(.red)
                } else if isSpeaking {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(ClarissaTheme.cyan)
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                    Text("Speaking...")
                        .foregroundStyle(ClarissaTheme.cyan)
                } else {
                    Image(systemName: "mic.fill")
                        .foregroundStyle(ClarissaTheme.purple)
                    Text("Voice Mode")
                        .foregroundStyle(ClarissaTheme.purple)
                }
            }
            .font(.subheadline.bold())

            Spacer()

            // Exit button
            Button {
                onExit()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
        .padding(.horizontal)
    }
}

#Preview {
    ChatView(viewModel: ChatViewModel())
}

