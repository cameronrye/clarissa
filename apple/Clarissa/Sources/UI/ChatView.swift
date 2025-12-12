import SwiftUI
#if os(iOS)
import UIKit
#endif

struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    @FocusState private var isInputFocused: Bool

    // Namespace for glass morphing transitions
    @Namespace private var inputNamespace
    @Namespace private var messageNamespace

    // Accessibility environment variables
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

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
                                onRetry: message.role == .assistant ? { viewModel.retryLastMessage() } : nil,
                                onSpeak: message.role == .assistant ? { text in viewModel.speak(text: text) } : nil,
                                onStopSpeaking: { viewModel.stopSpeaking() },
                                isSpeaking: viewModel.isSpeaking
                            )
                            .id(message.id)
                            .transition(.asymmetric(
                                insertion: message.role == .user
                                    ? .move(edge: .trailing).combined(with: .opacity)
                                    : .opacity,  // Assistant/tool messages just fade in (no slide)
                                removal: .opacity
                            ))
                        }
                        .animation(.easeOut(duration: 0.25), value: viewModel.messages.count)
                        
                        // Streaming content with typing indicator
                        if !viewModel.streamingContent.isEmpty {
                            StreamingMessageBubble(content: viewModel.streamingContent)
                                .id("streaming")
                        }

                        // Typing bubble indicator - shows what Clarissa is doing
                        if viewModel.thinkingStatus.isActive {
                            TypingBubble(
                                status: viewModel.thinkingStatus,
                                showCancel: viewModel.canCancel,
                                onCancel: { viewModel.cancelGeneration() }
                            )
                            .id("thinking")
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
                .onChange(of: viewModel.thinkingStatus) { _, newStatus in
                    if newStatus.isActive {
                        withAnimation {
                            proxy.scrollTo("thinking", anchor: .bottom)
                        }
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
                        HapticManager.shared.lightTap()
                        Task { await viewModel.toggleVoiceMode() }
                    }
                )
            }

            // Input area with glass effects
            inputAreaView
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
        #if os(macOS)
        // Focus the input field on appearance and handle keyboard navigation
        .onAppear {
            // Auto-focus the input field on macOS
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isInputFocused = true
            }
        }
        .onKeyPress(.escape) {
            // Cancel generation with Escape key
            if viewModel.isLoading {
                viewModel.cancelGeneration()
                return .handled
            }
            return .ignored
        }
        #endif
    }

    // MARK: - Input Area with Glass Effects

    @ViewBuilder
    private var inputAreaView: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            glassInputArea
        } else {
            legacyInputArea
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    private var glassInputArea: some View {
        GlassEffectContainer(spacing: 20) {
            HStack(spacing: 12) {
                // Voice input button with glass (speech recognition / listening)
                // Hidden when voice mode is active since VoiceModeIndicator handles voice
                if !viewModel.isVoiceModeActive {
                    voiceInputButton
                }

                // Text input field
                TextField("Message Clarissa...", text: $viewModel.inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .focused($isInputFocused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .onSubmit {
                        HapticManager.shared.mediumTap()
                        viewModel.sendMessage()
                    }
                    .accessibilityLabel("Message input")
                    .accessibilityHint("Type your message to Clarissa. Press return to send.")

                // Enhance prompt button - only shown when there's text
                if hasInputText {
                    enhanceButton
                }

                // Send button
                sendButton
            }
            .padding()
        }
    }

    /// Helper to check if input has text
    private var hasInputText: Bool {
        !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var legacyInputArea: some View {
        HStack(spacing: 12) {
            // Voice input button - hidden when voice mode is active
            if !viewModel.isVoiceModeActive {
                Button {
                    HapticManager.shared.mediumTap()
                    Task { await viewModel.toggleVoiceInput() }
                } label: {
                    ZStack {
                        if viewModel.isRecording {
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
                .accessibilityHint(viewModel.isRecording ? "Double-tap to stop recording and send transcribed text" : "Double-tap to speak your message instead of typing")
            }

            TextField("Message Clarissa...", text: $viewModel.inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($isInputFocused)
                .onSubmit {
                    HapticManager.shared.mediumTap()
                    viewModel.sendMessage()
                }
                .accessibilityLabel("Message input")
                .accessibilityHint("Type your message to Clarissa. Press return to send.")

            let sendDisabled = !hasInputText || viewModel.isLoading
            let enhanceDisabled = !hasInputText || viewModel.isLoading || viewModel.isEnhancing

            // Enhance prompt button - only shown when there's text
            if hasInputText {
                Button {
                    Task { await viewModel.enhanceCurrentPrompt() }
                } label: {
                    Image(systemName: "wand.and.stars")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(enhanceDisabled ? Color.secondary.opacity(0.3) : ClarissaTheme.cyan)
                        )
                        .symbolEffect(.pulse, isActive: viewModel.isEnhancing)
                }
                .disabled(enhanceDisabled)
                .accessibilityLabel("Enhance prompt")
                .accessibilityHint(enhanceDisabled ? "Type a message first to enable prompt enhancement" : "Double-tap to improve your prompt")
            }

            // Send button
            Button {
                HapticManager.shared.mediumTap()
                viewModel.sendMessage()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(sendDisabled ? Color.secondary.opacity(0.3) : ClarissaTheme.purple)
                    )
            }
            .disabled(sendDisabled)
            .accessibilityLabel("Send message")
            .accessibilityHint(sendDisabled ? "Type a message first, then double-tap to send" : "Double-tap to send your message to Clarissa")
        }
        .padding()
        .background(.bar)
    }

    // MARK: - Glass Input Components

    @available(iOS 26.0, macOS 26.0, *)
    private var voiceInputButton: some View {
        Button {
            HapticManager.shared.mediumTap()
            Task { await viewModel.toggleVoiceInput() }
        } label: {
            Image(systemName: viewModel.isRecording ? "waveform" : "mic")
                .font(.title2)
                .frame(width: 44, height: 44)
                .symbolEffect(.variableColor.iterative, options: .repeating, value: viewModel.isRecording)
        }
        .glassEffect(
            reduceMotion
                ? Glass.regular.tint(viewModel.isRecording ? ClarissaTheme.errorTint : nil)
                : Glass.regular.interactive().tint(viewModel.isRecording ? ClarissaTheme.errorTint : nil),
            in: .circle
        )
        .glassEffectID("voiceInput", in: inputNamespace)
        .animation(.bouncy, value: viewModel.isRecording)
        .accessibilityLabel(viewModel.isRecording ? "Stop recording" : "Start voice input")
        .accessibilityHint(viewModel.isRecording ? "Double-tap to stop recording and send transcribed text" : "Double-tap to speak your message instead of typing")
    }

    @available(iOS 26.0, macOS 26.0, *)
    private var enhanceButton: some View {
        let isDisabled = viewModel.isLoading || viewModel.isEnhancing

        return Button {
            Task { await viewModel.enhanceCurrentPrompt() }
        } label: {
            Image(systemName: "wand.and.stars")
                .font(.title2)
                .frame(width: 44, height: 44)
                .symbolEffect(.pulse, isActive: viewModel.isEnhancing)
        }
        .glassEffect(
            reduceMotion
                ? Glass.regular.tint(viewModel.isEnhancing ? ClarissaTheme.enhanceTint : nil)
                : Glass.regular.interactive().tint(viewModel.isEnhancing ? ClarissaTheme.enhanceTint : nil),
            in: .circle
        )
        .glassEffectID("enhance", in: inputNamespace)
        .animation(.bouncy, value: viewModel.isEnhancing)
        .disabled(isDisabled)
        .accessibilityLabel("Enhance prompt")
        .accessibilityHint(isDisabled ? "Processing..." : "Double-tap to improve your prompt")
    }

    @available(iOS 26.0, macOS 26.0, *)
    private var sendButton: some View {
        let isDisabled = !hasInputText || viewModel.isLoading

        return Button {
            HapticManager.shared.mediumTap()
            viewModel.sendMessage()
        } label: {
            Image(systemName: "arrow.up")
                .font(.title2)
                .frame(width: 44, height: 44)
        }
        .glassEffect(
            reduceMotion
                ? Glass.regular
                : Glass.regular.interactive(),
            in: .circle
        )
        .glassEffectID("send", in: inputNamespace)
        .disabled(isDisabled)
        .accessibilityLabel("Send message")
        .accessibilityHint(isDisabled ? "Type a message first, then double-tap to send" : "Double-tap to send your message to Clarissa")
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    var onRetry: (() -> Void)? = nil
    var onSpeak: ((String) -> Void)? = nil
    var onStopSpeaking: (() -> Void)? = nil
    var isSpeaking: Bool = false

    @State private var showCopied = false
    @State private var isHovered = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// Max width for message bubbles on larger screens (iPad/Mac)
    private var maxBubbleWidth: CGFloat? {
        horizontalSizeClass == .regular ? ClarissaConstants.maxMessageBubbleWidth : nil
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
                        #if os(macOS)
                        .scaleEffect(isHovered ? 1.01 : 1.0)
                        .shadow(color: isHovered ? .black.opacity(0.1) : .clear, radius: 4, y: 2)
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                isHovered = hovering
                            }
                        }
                        #endif
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
                        #if os(macOS)
                        .scaleEffect(isHovered ? 1.01 : 1.0)
                        .shadow(color: isHovered ? .black.opacity(0.1) : .clear, radius: 4, y: 2)
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                isHovered = hovering
                            }
                        }
                        #endif
                        .contextMenu {
                            copyButton
                            speakButton
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

    @ViewBuilder
    private var speakButton: some View {
        if isSpeaking {
            Button {
                onStopSpeaking?()
            } label: {
                Label("Stop Speaking", systemImage: "speaker.slash")
            }
        } else if let onSpeak = onSpeak {
            Button {
                HapticManager.shared.lightTap()
                onSpeak(message.content)
            } label: {
                Label("Speak", systemImage: "speaker.wave.2")
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
        horizontalSizeClass == .regular ? ClarissaConstants.maxMessageBubbleWidth : nil
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

/// Typing bubble indicator that looks like an incoming message with animated dots
/// Shows what Clarissa is currently doing (thinking, using a tool, processing)
struct TypingBubble: View {
    let status: ThinkingStatus
    var showCancel: Bool = false
    var onCancel: (() -> Void)?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var maxBubbleWidth: CGFloat? {
        horizontalSizeClass == .regular ? ClarissaConstants.maxMessageBubbleWidth : nil
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Bubble content
            HStack(spacing: 10) {
                // Animated dots
                TypingDotsView(reduceMotion: reduceMotion)

                // Status text
                Text(status.displayText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Cancel button
                if showCancel, let onCancel = onCancel {
                    Button {
                        HapticManager.shared.lightTap()
                        onCancel()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(ClarissaTheme.assistantBubble)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .frame(maxWidth: maxBubbleWidth, alignment: .leading)

            Spacer(minLength: 60)
        }
        .transition(.asymmetric(
            insertion: .move(edge: .leading).combined(with: .opacity),
            removal: .opacity
        ))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Clarissa is \(status.displayText.lowercased())")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// Animated typing dots (like iMessage) - uses shared AnimatedDotsView
private struct TypingDotsView: View {
    let reduceMotion: Bool

    var body: some View {
        // When reduceMotion is true, just show static dots (no animation)
        if reduceMotion {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(ClarissaTheme.purple)
                        .frame(width: 8, height: 8)
                        .opacity(0.6)
                }
            }
        } else {
            AnimatedDotsView(
                tint: ClarissaTheme.purple,
                dotSize: 8,
                dotSpacing: 4,
                animationInterval: 0.35,
                animateScale: true,
                respectReduceMotion: false  // We handle this manually above
            )
        }
    }
}

/// Empty state view with logo and suggested prompts
struct EmptyStateView: View {
    let onSuggestionTap: (String) -> Void

    @Namespace private var suggestionsNamespace
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

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

                if #available(iOS 26.0, macOS 26.0, *) {
                    glassSuggestionsList
                } else {
                    legacySuggestionsList
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: 500)
    }

    @available(iOS 26.0, macOS 26.0, *)
    private var glassSuggestionsList: some View {
        VStack(spacing: 8) {
            ForEach(suggestions, id: \.self) { suggestion in
                Button {
                    onSuggestionTap(suggestion)
                } label: {
                    HStack {
                        Text(suggestion)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "arrow.up")
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 12))
                .glassEffectID(suggestion, in: suggestionsNamespace)
            }
        }
    }

    private var legacySuggestionsList: some View {
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
                .background(reduceTransparency ? Color(ClarissaTheme.secondarySystemBackground) : ClarissaTheme.assistantBubble)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
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
                    historyDoneButton
                }
            }
            #else
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    historyDoneButton
                }
            }
            #endif
        }
        .tint(ClarissaTheme.purple)
        .task {
            await loadData()
        }
    }

    @ViewBuilder
    private var historyDoneButton: some View {
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
                            currentBadge
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

    /// Badge indicating current session - uses solid background per Liquid Glass guide
    /// (glass should not be applied to content layer elements like List rows)
    private var currentBadge: some View {
        Text("Current")
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(ClarissaTheme.purple)
            .clipShape(Capsule())
    }
}

/// Indicator shown when voice mode is active
struct VoiceModeIndicator: View {
    let isListening: Bool
    let isSpeaking: Bool
    let onExit: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var voiceModeNamespace

    /// Tint color based on current state
    private var stateTint: Color? {
        if isListening { return ClarissaTheme.listeningTint }
        if isSpeaking { return ClarissaTheme.speakingTint }
        return nil
    }

    /// Accessibility label for current state
    private var stateAccessibilityLabel: String {
        if isListening { return "Voice mode active, listening for your voice" }
        if isSpeaking { return "Voice mode active, Clarissa is speaking" }
        return "Voice mode active, ready to listen"
    }

    var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            glassVoiceModeContent
        } else {
            legacyVoiceModeContent
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    private var glassVoiceModeContent: some View {
        GlassEffectContainer(spacing: 20) {
            HStack(spacing: 12) {
                // Status indicator with glass
                statusContent
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .glassEffect(.regular.tint(stateTint), in: RoundedRectangle(cornerRadius: 10))
                    .glassEffectID("status", in: voiceModeNamespace)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(stateAccessibilityLabel)
                    .accessibilityAddTraits(.updatesFrequently)

                Spacer()

                // Exit button with glass
                Button {
                    HapticManager.shared.lightTap()
                    onExit()
                } label: {
                    Image(systemName: "xmark")
                        .font(.title3)
                        .frame(width: 36, height: 36)
                }
                .glassEffect(reduceMotion ? .regular : .regular.interactive())
                .glassEffectID("exit", in: voiceModeNamespace)
                .accessibilityLabel("Exit voice mode")
                .accessibilityHint("Double-tap to return to text input mode")
            }
            .padding(.horizontal)
        }
    }

    private var legacyVoiceModeContent: some View {
        HStack(spacing: 12) {
            statusContent
                .font(.subheadline.bold())
                .accessibilityElement(children: .combine)
                .accessibilityLabel(stateAccessibilityLabel)

            Spacer()

            Button {
                HapticManager.shared.lightTap()
                onExit()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Exit voice mode")
            .accessibilityHint("Double-tap to return to text input mode")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(ClarissaTheme.secondarySystemBackground))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var statusContent: some View {
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
    }
}

#Preview {
    ChatView(viewModel: ChatViewModel())
}

