import SwiftUI
import PhotosUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    @FocusState private var isInputFocused: Bool

    // Photo picker state
    @State private var selectedPhotoItem: PhotosPickerItem?

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
            } else if viewModel.isSwitchingSession {
                // Loading state while switching sessions
                Spacer()
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(ClarissaTheme.purple)
                    Text("Loading conversation...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else if viewModel.messages.isEmpty && viewModel.streamingContent.isEmpty && !viewModel.isLoading {
                // Empty state with suggestions - wrapped in ScrollView for keyboard avoidance
                ScrollView {
                    EmptyStateView(onSuggestionTap: { suggestion in
                        viewModel.inputText = suggestion
                        viewModel.sendMessage()
                    })
                }
                .scrollDismissesKeyboard(.interactively)

                Divider()

                // Input area for empty state
                inputAreaView
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
                .onChange(of: viewModel.streamingContent) { _, newValue in
                    // Only scroll when there's active streaming content to avoid
                    // attempting to scroll to a view that no longer exists.
                    guard !newValue.isEmpty else { return }
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
        #if os(iOS)
        .modifier(CameraCaptureModifier(viewModel: viewModel))
        #endif
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
            VStack(spacing: 8) {
                // Image preview if attached
                if let imageData = viewModel.attachedImagePreview {
                    imagePreviewView(data: imageData)
                        .transition(.scale.combined(with: .opacity))
                }

                HStack(spacing: 12) {
                    // Voice input button with glass (speech recognition / listening)
                    // Hidden when voice mode is active since VoiceModeIndicator handles voice
                    if !viewModel.isVoiceModeActive {
                        voiceInputButton
                    }

                    // Image picker button
                    imagePickerButton

                    // Camera button (iOS only)
                    #if os(iOS)
                    cameraButton
                    #endif

                    // Text input field
                    TextField("Message Clarissa...", text: $viewModel.inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...5)
                        .focused($isInputFocused)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.clear)
                        .contentShape(Rectangle())
                        .onSubmit {
                            HapticManager.shared.mediumTap()
                            viewModel.sendMessage()
                        }
                        .accessibilityLabel("Message input")
                        .accessibilityHint("Type your message to Clarissa. Press return to send.")

                    // Enhance prompt button - only shown when there's text
                    if hasInputText {
                        enhanceButton
                            .transition(.scale.combined(with: .opacity))
                    }

                    // Send button
                    sendButton
                }
            }
            .animation(.easeInOut(duration: 0.2), value: hasInputText)
            .animation(.easeInOut(duration: 0.2), value: viewModel.attachedImagePreview != nil)
            .padding()
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    viewModel.attachImage(data)
                }
                selectedPhotoItem = nil
            }
        }
    }

    /// Helper to check if input has text
    private var hasInputText: Bool {
        !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var legacyInputArea: some View {
        VStack(spacing: 8) {
            // Image preview if attached
            if let imageData = viewModel.attachedImagePreview {
                legacyImagePreviewView(data: imageData)
                    .transition(.scale.combined(with: .opacity))
            }

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

                // Image picker button
                legacyImagePickerButton

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

                let hasContent = hasInputText || viewModel.attachedImageData != nil
                let sendDisabled = !hasContent || viewModel.isLoading
                let enhanceDisabled = !hasInputText || viewModel.isLoading || viewModel.isEnhancing

                // Enhance prompt button - only shown when there's text
                if hasInputText {
                    Button {
                        Task { await viewModel.enhanceCurrentPrompt() }
                    } label: {
                        ZStack {
                            Image(systemName: "wand.and.stars")
                                .font(.title2)
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(
                                    Circle()
                                        .fill(viewModel.enhancementFailed ? Color.red.opacity(0.6) : (enhanceDisabled ? Color.secondary.opacity(0.3) : ClarissaTheme.cyan))
                                )
                                .symbolEffect(.pulse, isActive: viewModel.isEnhancing)

                            // Subtle failure indicator - small "x" badge
                            if viewModel.enhancementFailed {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 14, height: 14)
                                    .background(Circle().fill(Color.red.opacity(0.9)))
                                    .offset(x: 12, y: -12)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                    }
                    .disabled(enhanceDisabled)
                    .animation(.easeInOut(duration: 0.2), value: viewModel.enhancementFailed)
                    .accessibilityLabel(viewModel.enhancementFailed ? "Enhancement unavailable" : "Enhance prompt")
                    .accessibilityHint(viewModel.enhancementFailed ? "Enhancement couldn't complete. Try again." : (enhanceDisabled ? "Type a message first to enable prompt enhancement" : "Double-tap to improve your prompt"))
                    .transition(.scale.combined(with: .opacity))
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
                .accessibilityHint(sendDisabled ? "Type a message or attach an image first" : "Double-tap to send your message to Clarissa")
            }
        }
        .animation(.easeInOut(duration: 0.2), value: hasInputText)
        .animation(.easeInOut(duration: 0.2), value: viewModel.attachedImagePreview != nil)
        .padding()
        .background(.bar)
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    viewModel.attachImage(data)
                }
                selectedPhotoItem = nil
            }
        }
    }

    // MARK: - Legacy Image Picker Components

    private var legacyImagePickerButton: some View {
        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
            Image(systemName: "photo.circle.fill")
                .font(.title2)
                .foregroundStyle(ClarissaTheme.gradient)
        }
        .accessibilityLabel("Attach image")
        .accessibilityHint("Double-tap to select an image for analysis")
    }

    private func legacyImagePreviewView(data: Data) -> some View {
        HStack {
            #if canImport(UIKit)
            if let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            #elseif canImport(AppKit)
            if let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            #endif

            Button {
                viewModel.removeAttachedImage()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove image")
            .accessibilityHint("Double-tap to remove the attached image")

            Spacer()
        }
        .padding(.horizontal, 8)
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
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: viewModel.isRecording)
        }
        .buttonStyle(.plain)
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
        let failedTint = Color.red.opacity(0.6)

        return Button {
            Task { await viewModel.enhanceCurrentPrompt() }
        } label: {
            ZStack {
                Image(systemName: "wand.and.stars")
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .symbolEffect(.pulse, isActive: viewModel.isEnhancing)

                // Subtle failure indicator - small "x" badge
                if viewModel.enhancementFailed {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Color.red.opacity(0.8)))
                        .offset(x: 14, y: -14)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .buttonStyle(.plain)
        .glassEffect(
            reduceMotion
                ? Glass.regular.tint(viewModel.enhancementFailed ? failedTint : (viewModel.isEnhancing ? ClarissaTheme.enhanceTint : nil))
                : Glass.regular.interactive().tint(viewModel.enhancementFailed ? failedTint : (viewModel.isEnhancing ? ClarissaTheme.enhanceTint : nil)),
            in: .circle
        )
        .glassEffectID("enhance", in: inputNamespace)
        .animation(.bouncy, value: viewModel.isEnhancing)
        .animation(.easeInOut(duration: 0.2), value: viewModel.enhancementFailed)
        .disabled(isDisabled)
        .accessibilityLabel(viewModel.enhancementFailed ? "Enhancement unavailable" : "Enhance prompt")
        .accessibilityHint(viewModel.enhancementFailed ? "Enhancement couldn't complete. Try again." : (isDisabled ? "Processing..." : "Double-tap to improve your prompt"))
    }

    @available(iOS 26.0, macOS 26.0, *)
    private var sendButton: some View {
        let hasContent = hasInputText || viewModel.attachedImageData != nil
        let isDisabled = !hasContent || viewModel.isLoading

        return Button {
            HapticManager.shared.mediumTap()
            viewModel.sendMessage()
        } label: {
            Image(systemName: "arrow.up")
                .font(.title2)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .glassEffect(
            reduceMotion
                ? Glass.regular
                : Glass.regular.interactive(),
            in: .circle
        )
        .glassEffectID("send", in: inputNamespace)
        .disabled(isDisabled)
        .accessibilityLabel("Send message")
        .accessibilityHint(isDisabled ? "Type a message or attach an image first" : "Double-tap to send your message to Clarissa")
    }

    // MARK: - Image Picker Components

    @available(iOS 26.0, macOS 26.0, *)
    private var imagePickerButton: some View {
        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
            Image(systemName: "photo")
                .font(.title2)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .glassEffect(
            reduceMotion
                ? Glass.regular
                : Glass.regular.interactive(),
            in: .circle
        )
        .glassEffectID("imagePicker", in: inputNamespace)
        .accessibilityLabel("Attach image")
        .accessibilityHint("Double-tap to select an image for analysis")
    }

    #if os(iOS)
    @available(iOS 26.0, *)
    private var cameraButton: some View {
        Button {
            HapticManager.shared.lightTap()
            viewModel.showCamera()
        } label: {
            Image(systemName: "camera")
                .font(.title2)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .glassEffect(
            reduceMotion
                ? Glass.regular
                : Glass.regular.interactive(),
            in: .circle
        )
        .glassEffectID("camera", in: inputNamespace)
        .accessibilityLabel("Take photo")
        .accessibilityHint("Double-tap to open camera and capture an image for analysis")
    }
    #endif

    @available(iOS 26.0, macOS 26.0, *)
    private func imagePreviewView(data: Data) -> some View {
        HStack {
            #if canImport(UIKit)
            if let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            #elseif canImport(AppKit)
            if let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            #endif

            Button {
                viewModel.removeAttachedImage()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove image")
            .accessibilityHint("Double-tap to remove the attached image")

            Spacer()
        }
        .padding(.horizontal, 8)
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
    #if os(iOS)
    @State private var showShareSheet = false
    #endif
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
                            shareButton
                        }
                        #if os(iOS)
                        .sheet(isPresented: $showShareSheet) {
                            ActivityViewController(activityItems: [message.content])
                        }
                        #endif
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
                            shareButton
                            speakButton
                            if let onRetry = onRetry {
                                Button {
                                    onRetry()
                                } label: {
                                    Label("Retry", systemImage: "arrow.clockwise")
                                }
                            }
                        }
                        #if os(iOS)
                        .sheet(isPresented: $showShareSheet) {
                            ActivityViewController(activityItems: [message.content])
                        }
                        #endif
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

    private var shareButton: some View {
        Button {
            #if os(iOS)
            HapticManager.shared.lightTap()
            showShareSheet = true
            #elseif os(macOS)
            // On macOS, use the share picker
            let picker = NSSharingServicePicker(items: [message.content])
            if let contentView = NSApp.keyWindow?.contentView {
                picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
            }
            #endif
        } label: {
            Label("Share", systemImage: "square.and.arrow.up.circle")
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
            // User messages with optional image
            VStack(alignment: .trailing, spacing: 8) {
                if let imageData = message.imageData {
                    #if canImport(UIKit)
                    if let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 200, maxHeight: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    #elseif canImport(AppKit)
                    if let nsImage = NSImage(data: imageData) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 200, maxHeight: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    #endif
                }
                Text(message.content)
            }
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
    @State private var cursorVisible = false
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
            // Start a repeating opacity animation for the cursor
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                cursorVisible.toggle()
            }
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

/// Empty state view with logo and suggested prompts based on enabled tools
struct EmptyStateView: View {
    let onSuggestionTap: (String) -> Void

    @Namespace private var suggestionsNamespace
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ObservedObject private var toolSettings = ToolSettings.shared

    /// Example prompts for each tool, keyed by tool ID
    private static let toolPrompts: [String: [String]] = [
        "weather": [
            "What's the weather like today?",
            "Will it rain this weekend?",
            "What's the forecast for tomorrow?"
        ],
        "calendar": [
            "What's on my calendar today?",
            "Schedule a meeting for tomorrow at 2pm",
            "Do I have any events this week?"
        ],
        "reminders": [
            "Remind me to call mom tomorrow",
            "Set a reminder for 9am",
            "What are my pending tasks?"
        ],
        "contacts": [
            "What's John's phone number?",
            "Find Sarah's email address",
            "Look up my dentist's contact"
        ],
        "calculator": [
            "What's 15% tip on $47.50?",
            "Calculate 234 times 56",
            "What's 20% of 85?"
        ],
        "location": [
            "Where am I right now?",
            "What's my current address?"
        ],
        "remember": [
            "Remember that I prefer dark roast coffee",
            "My favorite color is blue, remember that"
        ],
        "web_fetch": [
            "Fetch the content from example.com"
        ]
    ]

    /// General prompts always available (task-oriented, things the model can actually do)
    private static let generalPrompts = [
        "What can you help me with?",
        "What day is it today?",
        "Help me draft a quick message"
    ]

    /// Generate suggestions based on enabled tools
    private var suggestions: [String] {
        var prompts: [String] = []
        let enabledTools = toolSettings.enabledToolNames

        // Add one prompt from each enabled tool (randomized)
        for toolId in enabledTools {
            if let toolPromptList = Self.toolPrompts[toolId],
               let prompt = toolPromptList.randomElement() {
                prompts.append(prompt)
            }
        }

        // Shuffle and limit to 4 suggestions
        prompts.shuffle()
        prompts = Array(prompts.prefix(3))

        // Always add one general prompt
        if let generalPrompt = Self.generalPrompts.randomElement() {
            prompts.append(generalPrompt)
        }

        return prompts
    }

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

                Text("Type a message below to get started")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
            }

            Spacer()

            // Suggested prompts
            VStack(alignment: .leading, spacing: 8) {
                Text("Or try one of these:")
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

/// View for displaying tool execution status with optional rich result display
struct ToolStatusView: View {
    let message: ChatMessage
    var onRetry: (() -> Void)? = nil

    /// Try to parse the tool result into a displayable format
    private var parsedResult: AnyToolResult? {
        guard let toolName = message.toolName,
              let toolResult = message.toolResult,
              message.toolStatus == .completed else {
            return nil
        }
        return ToolResultParser.parse(toolName: toolName, jsonResult: toolResult)
    }

    /// Color based on tool status with accessibility in mind
    private var statusColor: Color {
        switch message.toolStatus {
        case .running:
            return ClarissaTheme.purple
        case .completed:
            return ClarissaTheme.cyan
        case .failed:
            return .red
        case .none:
            return ClarissaTheme.cyan
        }
    }

    /// Icon based on tool status
    private var statusIcon: String {
        switch message.toolStatus {
        case .running:
            return "circle.dotted"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .none:
            return "circle.fill"
        }
    }

    var body: some View {
        if let result = parsedResult {
            // Rich result card for parseable tool results
            ToolResultCard(
                toolName: message.toolName ?? "Tool",
                displayName: message.content,
                result: result,
                status: message.toolStatus ?? .completed
            )
        } else {
            // Simple status view for running/failed/unparseable results
            simpleStatusView
        }
    }

    private var simpleStatusView: some View {
        HStack(spacing: 8) {
            if message.toolStatus == .running {
                ProgressView()
                    .controlSize(.small)
                    .tint(statusColor)
            } else {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
            }

            Text(message.content)
                .font(.subheadline)

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
        .background(statusColor.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// View for browsing and switching between past sessions
struct SessionHistoryView: View {
    @ObservedObject var viewModel: ChatViewModel
    let onDismiss: () -> Void
    @State private var sessions: [Session] = []
    @State private var currentSessionId: UUID?
    @State private var isLoading: Bool = true
    @State private var sessionToDelete: Session?
    @State private var showDeleteAlert: Bool = false
    #if os(iOS)
    @State private var editMode: EditMode = .inactive
    @State private var selectedSessions: Set<UUID> = []
    @State private var showDeleteConfirmation: Bool = false
    #endif

    private var isEditing: Bool {
        #if os(iOS)
        return editMode == .active
        #else
        return false
        #endif
    }

    var body: some View {
        NavigationStack {
            sessionHistoryList
        }
        .tint(ClarissaTheme.purple)
        .task {
            await loadData()
            isLoading = false
        }
        .onChange(of: viewModel.sessionVersion) { _, _ in
            Task {
                await loadData()
            }
        }
        .alert("Delete Conversation", isPresented: $showDeleteAlert, presenting: sessionToDelete) { session in
            Button("Delete", role: .destructive) {
                Task {
                    await viewModel.deleteSession(id: session.id)
                    sessions.removeAll { $0.id == session.id }
                    // Refresh currentSessionId since it may have changed after deletion
                    currentSessionId = await viewModel.getCurrentSessionId()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Are you sure you want to delete this conversation? This action cannot be undone.")
        }
        #if os(iOS)
        .onChange(of: editMode) { _, newMode in
            if newMode == .inactive {
                selectedSessions.removeAll()
            }
        }
        .confirmationDialog(
            "Delete \(selectedSessions.count) Conversation\(selectedSessions.count == 1 ? "" : "s")?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteSelectedSessions()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        #endif
    }

    @ViewBuilder
    private var sessionHistoryList: some View {
        #if os(iOS)
        List(selection: $selectedSessions) {
            sessionHistoryListContent
        }
        .environment(\.editMode, $editMode)
        .navigationTitle("History")
        .refreshable {
            await loadData()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !sessions.isEmpty && !isLoading {
                    editButton
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if isEditing && !selectedSessions.isEmpty {
                    deleteSelectedButton
                } else {
                    historyDoneButton
                }
            }
        }
        #else
        List {
            sessionHistoryListContent
        }
        .navigationTitle("History")
        .refreshable {
            await loadData()
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                historyDoneButton
            }
        }
        #endif
    }

    @ViewBuilder
    private var sessionHistoryListContent: some View {
        if isLoading {
            HStack {
                Spacer()
                ProgressView()
                    .tint(ClarissaTheme.purple)
                Spacer()
            }
            .listRowBackground(Color.clear)
        } else if sessions.isEmpty {
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
                    isEditing: isEditing,
                    onTap: {
                        Task {
                            await viewModel.switchToSession(id: session.id)
                            onDismiss()
                        }
                    },
                    onDelete: {
                        sessionToDelete = session
                        showDeleteAlert = true
                    },
                    onRename: { newTitle in
                        Task {
                            await viewModel.renameSession(id: session.id, newTitle: newTitle)
                            // Update local array
                            if let index = sessions.firstIndex(where: { $0.id == session.id }) {
                                sessions[index] = Session(
                                    id: session.id,
                                    title: newTitle,
                                    messages: session.messages,
                                    createdAt: session.createdAt,
                                    updatedAt: Date()
                                )
                            }
                        }
                    }
                )
                .tag(session.id)
            }
            #if os(iOS)
            .onDelete(perform: deleteSessions)
            #endif
        }
    }

    #if os(iOS)
    @ViewBuilder
    private var editButton: some View {
        Button {
            HapticManager.shared.lightTap()
            withAnimation {
                editMode = isEditing ? .inactive : .active
            }
        } label: {
            Text(isEditing ? "Done" : "Select")
        }
        .foregroundStyle(ClarissaTheme.purple)
    }

    @ViewBuilder
    private var deleteSelectedButton: some View {
        Button(role: .destructive) {
            HapticManager.shared.warning()
            showDeleteConfirmation = true
        } label: {
            Text("Delete (\(selectedSessions.count))")
        }
    }
    #endif

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

    #if os(iOS)
    private func deleteSessions(at offsets: IndexSet) {
        HapticManager.shared.warning()
        let sessionsToDelete = offsets.map { sessions[$0] }
        sessions.remove(atOffsets: offsets)
        Task {
            for session in sessionsToDelete {
                await viewModel.deleteSession(id: session.id)
            }
            // Refresh currentSessionId since it may have changed after deletion
            currentSessionId = await viewModel.getCurrentSessionId()
        }
    }

    private func deleteSelectedSessions() {
        HapticManager.shared.warning()
        let idsToDelete = selectedSessions
        sessions.removeAll { idsToDelete.contains($0.id) }
        selectedSessions.removeAll()
        withAnimation {
            editMode = .inactive
        }
        Task {
            for id in idsToDelete {
                await viewModel.deleteSession(id: id)
            }
            // Refresh currentSessionId since it may have changed after deletion
            currentSessionId = await viewModel.getCurrentSessionId()
        }
    }
    #endif
}

/// Row view for a single session in history
struct SessionRowView: View {
    let session: Session
    let isCurrentSession: Bool
    var isEditing: Bool = false
    let onTap: () -> Void
    var onDelete: (() -> Void)? = nil
    var onRename: ((String) -> Void)? = nil

    @State private var isRenamingInline: Bool = false
    @State private var editingTitle: String = ""
    @FocusState private var isTitleFieldFocused: Bool

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
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if isRenamingInline {
                        TextField("Title", text: $editingTitle)
                            .font(.headline)
                            .textFieldStyle(.plain)
                            .focused($isTitleFieldFocused)
                            .onSubmit {
                                saveRename()
                            }
                            .onKeyPress(.escape) {
                                cancelRename()
                                return .handled
                            }
                    } else {
                        Text(session.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }

                    if isCurrentSession && !isRenamingInline {
                        currentBadge
                    }
                }

                // Message preview
                if let preview = messagePreview, !isRenamingInline {
                    Text(preview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if !isRenamingInline {
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
            }

            Spacer()

            if !isEditing && !isRenamingInline {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isRenamingInline && !isEditing {
                onTap()
            }
        }
        .gesture(
            TapGesture(count: 2)
                .onEnded {
                    startRename()
                }
        )
        .contextMenu {
            Button {
                startRename()
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            if let onDelete = onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        #if os(iOS)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                startRename()
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(ClarissaTheme.purple)
        }
        #endif
    }

    private func startRename() {
        editingTitle = session.title
        isRenamingInline = true
        isTitleFieldFocused = true
    }

    private func saveRename() {
        let trimmed = editingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != session.title {
            onRename?(trimmed)
        }
        isRenamingInline = false
        isTitleFieldFocused = false
    }

    private func cancelRename() {
        isRenamingInline = false
        isTitleFieldFocused = false
        editingTitle = session.title
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
                .buttonStyle(.plain)
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

// MARK: - Activity View Controller for iOS Share

#if os(iOS)
import UIKit

struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

// MARK: - Camera Capture Modifier

#if os(iOS)
/// ViewModifier that adds camera capture sheet to the view
struct CameraCaptureModifier: ViewModifier {
    @ObservedObject var viewModel: ChatViewModel

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .fullScreenCover(isPresented: $viewModel.showCameraCapture) {
                    CameraCaptureView(
                        onImageCaptured: { capturedImage in
                            viewModel.handleCameraCapture(capturedImage)
                        },
                        onDismiss: {
                            viewModel.dismissCamera()
                        }
                    )
                }
        } else {
            content
        }
    }
}
#endif

#Preview {
    ChatView(viewModel: ChatViewModel())
}
