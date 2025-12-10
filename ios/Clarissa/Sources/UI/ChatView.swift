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
                        }
                        
                        // Streaming content
                        if !viewModel.streamingContent.isEmpty {
                            MessageBubble(
                                message: ChatMessage(
                                    role: .assistant,
                                    content: viewModel.streamingContent
                                )
                            )
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
            
            // Input area
            HStack(spacing: 12) {
                TextField("Message Clarissa...", text: $viewModel.inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .focused($isInputFocused)
                    .onSubmit {
                        triggerHaptic()
                        viewModel.sendMessage()
                    }

                let isDisabled = viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading

                Button {
                    triggerHaptic()
                    viewModel.sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(isDisabled ? AnyShapeStyle(Color.secondary) : AnyShapeStyle(ClarissaTheme.gradient))
                }
                .disabled(isDisabled)
            }
            .padding()
            .background(.bar)
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

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if message.role == .tool {
                    ToolStatusView(message: message)
                } else if message.role == .user {
                    messageContent
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(ClarissaTheme.userBubbleGradient)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .contextMenu {
                            copyButton
                        }
                } else {
                    messageContent
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(ClarissaTheme.assistantBubble)
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
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
}

/// View for displaying tool execution status
struct ToolStatusView: View {
    let message: ChatMessage

    var body: some View {
        HStack(spacing: 8) {
            if message.toolStatus == .running {
                ProgressView()
                    .controlSize(.small)
                    .tint(ClarissaTheme.cyan)
            } else {
                Image(systemName: message.toolStatus == .completed ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(message.toolStatus == .completed ? ClarissaTheme.cyan : .red)
            }

            Text(message.content)
                .font(.subheadline)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(ClarissaTheme.cyan.opacity(0.1))
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

    var body: some View {
        NavigationStack {
            List {
                if sessions.isEmpty {
                    Text("No conversation history yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sessions) { session in
                        Button {
                            Task {
                                await viewModel.switchToSession(id: session.id)
                                onDismiss()
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                HStack {
                                    Text("\(session.messages.count) messages")
                                    Text("•")
                                    Text(session.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .onDelete(perform: deleteSessions)
                }
            }
            .navigationTitle("History")
            .refreshable {
                sessions = await viewModel.getAllSessions()
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
            sessions = await viewModel.getAllSessions()
        }
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

#Preview {
    ChatView(viewModel: ChatViewModel())
}

