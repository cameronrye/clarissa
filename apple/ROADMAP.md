# Clarissa Apple Roadmap

> Native iOS and macOS AI assistant with on-device Apple Intelligence

---

## Completed Features (v1.0.0)

### AI & Conversations

- [x] Apple Foundation Models integration with native tool calling
- [x] OpenRouter cloud fallback with 100+ model options
- [x] ReAct agent loop for multi-step reasoning
- [x] Streaming responses with real-time display
- [x] Session persistence with auto-generated titles
- [x] Long-term memory across conversations
- [x] Foundation Models prewarming for faster first response
- [x] Tool limit handling (max 10 for Foundation Models)

### Voice System

- [x] On-device speech recognition (Speech framework)
- [x] Text-to-speech with Siri voices
- [x] Voice mode for hands-free conversation
- [x] Configurable speech rate
- [x] Audio session management for interruptions
- [x] Bluetooth and headphone support

### Tools

- [x] Calendar - EventKit event management
- [x] Contacts - Contact search and display
- [x] Reminders - EventKit reminder management
- [x] Weather - WeatherKit current and forecast
- [x] Location - CoreLocation with geocoding
- [x] Web Fetch - URL content fetching
- [x] Calculator - Math expression evaluation
- [x] Remember - Long-term memory storage
- [x] Tool settings UI with enable/disable
- [x] Image analysis tool (basic)

### User Interface

- [x] iOS 26 Liquid Glass design system
- [x] Adaptive navigation (iPhone/iPad/Mac)
- [x] Tab bar minimization on scroll
- [x] Glass morphing transitions
- [x] Onboarding flow
- [x] Context window visualization
- [x] Glass thinking indicator
- [x] Haptic feedback
- [x] Full accessibility support

### Platform Integration

- [x] Siri Shortcuts (Ask Clarissa, New Conversation, Voice Mode)
- [x] macOS menu bar commands
- [x] macOS keyboard shortcuts
- [x] Keychain API key storage
- [x] iCloud sync for memories (NSUbiquitousKeyValueStore)

---

## Roadmap: Apple ML & AI Integration

Based on [Apple's Foundation Models framework](https://developer.apple.com/documentation/FoundationModels), [WWDC25 announcements](https://developer.apple.com/videos/play/wwdc2025/286/), and the [Apple Intelligence technical report](https://machinelearning.apple.com/research/apple-foundation-models-2025-updates).

### High Priority

#### 1. SpeechAnalyzer Upgrade

Replace legacy Speech framework with new SpeechAnalyzer API (iOS 26+).

- [x] Integrate `SpeechAnalyzer` for real-time transcription
- [x] Add `SpeechTranscriber` for audio file transcription
- [x] Leverage streaming transcription with advanced accuracy
- [x] Multi-language transcription support (15 languages)

**Why**: SpeechAnalyzer is dramatically faster and more accurate than the legacy Speech framework. Powers Notes and Voice Memos transcription in iOS 26.

**Resources**:

- [WWDC25: Bring advanced speech-to-text to your app](https://developer.apple.com/videos/play/wwdc2025/277/)
- [SpeechAnalyzer Documentation](https://developer.apple.com/documentation/Speech/bringing-advanced-speech-to-text-capabilities-to-your-app)

#### 2. Guided Generation with @Generable

Implement structured output using Foundation Models' guided generation.

- [x] Create `@Generable` structs for action item extraction
- [x] Add `@Guide` annotations for output constraints
- [x] Implement `PartiallyGenerated` types for streaming UI
- [x] Use guided generation for calendar event creation
- [x] Extract entities (people, places, dates) with guaranteed structure

**Why**: Guided generation guarantees structural correctness through constrained decoding. No more parsing JSON or handling malformed responses.

**Example**:

```swift
@Generable
struct ActionItems {
    @Guide(description: "Tasks extracted from conversation", .count(1...5))
    var tasks: [Task]

    @Guide(description: "Calendar events to create")
    var events: [CalendarEvent]
}
```

**Resources**:

- [WWDC25: Meet the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2025/286/)
- [WWDC25: Deep dive into the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2025/301/)

#### 3. Content Tagging Adapter

Leverage Apple's specialized content tagging model.

- [x] Integrate `SystemLanguageModel(useCase: .contentTagging)`
- [x] Implement topic detection for conversations
- [x] Add entity extraction (people, places, organizations)
- [x] Detect emotions and actions in user messages
- [x] Auto-tag saved memories with topics

**Why**: The content tagging adapter is specifically trained for extraction tasks and outperforms the general model for these use cases.

**Example**:

```swift
@Generable
struct ConversationTags {
    @Guide(.maximumCount(5))
    let topics: [String]
    @Guide(.maximumCount(3))
    let emotions: [String]
    @Guide(.maximumCount(3))
    let actions: [String]
}

let session = LanguageModelSession(
    model: SystemLanguageModel(useCase: .contentTagging),
    instructions: "Extract topics, emotions, and actions from the text."
)
```

#### 4. Enhanced Image Understanding

Upgrade ImageAnalysisTool with Foundation Models vision capabilities.

- [x] Process images with Foundation Models multimodal input
- [x] Extract text from photos (receipts, documents, screenshots)
- [x] Understand visual context for better responses
- [x] Add camera integration for live image analysis
- [x] Support multi-image reasoning

**Why**: The on-device model now includes a 300M parameter vision encoder (ViTDet-L) that can understand images alongside text.

**Resources**:

- [Apple Foundation Models Tech Report 2025](https://machinelearning.apple.com/research/apple-foundation-models-tech-report-2025)

### Medium Priority

#### 5. Inline Siri Responses

Enable Siri to answer without opening the app.

- [x] Create `ReturnsValue<String>` intents for inline responses
- [x] Add parameterized intents for common queries
- [x] Implement background Foundation Models inference
- [x] Support follow-up questions in Siri

**Why**: Current intents require opening the app. Inline responses provide a seamless Siri experience.

**Example**:

```swift
struct InlineAskIntent: AppIntent {
    @Parameter(title: "Question")
    var question: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let session = LanguageModelSession()
        let response = try await session.respond(to: question)
        return .result(value: response.content)
    }
}
```

#### 6. Document OCR Tool

Add document scanning using Vision framework updates.

- [x] Implement full-document text recognition
- [x] Add PDF text extraction
- [x] Support handwriting recognition
- [x] Integrate with camera for live document capture
- [x] Extract structured data (tables, forms)

**Why**: iOS 26 Vision framework includes enhanced document recognition that handles entire documents, not just regions.

**Resources**:

- [WWDC25: Read documents using the Vision framework](https://developer.apple.com/videos/play/wwdc2025/272/)

#### 7. Streaming Partial Generation UI

Leverage `PartiallyGenerated` types for responsive streaming.

- [x] Implement snapshot streaming in ChatView
- [x] Add progressive UI updates during generation
- [x] Use SwiftUI animations to enhance perceived speed
- [x] Order struct properties for optimal streaming display

**Why**: Snapshot streaming with partial types provides better UX than raw token streaming, especially for structured outputs.

**Example**:

```swift
@State private var plan: TripPlan.PartiallyGenerated?

for try await partial in session.streamResponse(generating: TripPlan.self) {
    withAnimation(.smooth) {
        plan = partial
    }
}
```

#### 8. Private Cloud Compute Fallback

Integrate Apple's privacy-preserving server inference.

- [x] Detect when task exceeds on-device capabilities
- [x] Seamlessly route to Private Cloud Compute
- [x] Maintain privacy guarantees with PCC
- [x] Handle PCC availability gracefully

**Why**: Complex reasoning tasks may exceed the 3B on-device model. PCC provides server-scale inference while maintaining Apple's privacy guarantees.

### Lower Priority

#### 9. Custom Adapter Training

Train Clarissa-specific adapters for specialized behaviors.

- [ ] Set up Apple's adapter training toolkit (Python)
- [ ] Create training data for Clarissa's conversation style
- [ ] Train rank-32 adapters for memory handling
- [ ] Implement adapter versioning for OS updates
- [ ] Test adapter quality regression

**Why**: Custom adapters can teach the model entirely new skills specific to Clarissa. However, they require retraining with each base model update.

**Resources**:

- [Adapter Training Toolkit](https://developer.apple.com/documentation/FoundationModels)

#### 10. BNNSGraph Audio Processing

Optimize real-time audio with Accelerate framework.

- [ ] Implement BNNSGraph for voice activity detection
- [ ] Add low-latency audio preprocessing
- [ ] Optimize voice mode power consumption
- [ ] Support real-time audio effects

**Why**: BNNSGraph provides strict latency and memory control for real-time ML on CPU, ideal for voice processing.

#### 11. MLX Integration

Explore MLX for advanced local model capabilities.

- [ ] Evaluate MLX for specialized tasks
- [ ] Implement model fine-tuning on device
- [ ] Add model comparison features
- [ ] Support custom model deployment

**Why**: MLX enables training and fine-tuning on Apple Silicon's unified memory, opening possibilities for personalization.

---

## Platform Expansion

### watchOS

- [x] Companion app with voice-first interface
- [x] Complications for quick actions (circular, corner, rectangular, inline)
- [x] Watch-to-phone handoff
- [ ] Standalone mode with on-device AI

### visionOS

- [ ] Spatial interface design
- [ ] Eye tracking for navigation
- [ ] Virtual keyboard integration
- [ ] Immersive voice mode

### CarPlay

- [x] Dashboard quick actions
- [x] Voice-only interaction mode
- [ ] Navigation integration
- [x] Hands-free conversation

### Widgets & Extensions

- [x] Interactive widgets for quick questions (QuickAskWidget, ConversationWidget)
- [x] Share extension for web pages
- [x] Lock Screen widgets (accessoryCircular, accessoryRectangular)
- [x] Control Center button (iOS 18+)
- [x] Live Activities for long-running tasks

---

## Architecture Goals

### Performance

- Minimize memory footprint on device
- Optimize Foundation Models session reuse
- Efficient context window management (4096 tokens)
- Background task completion
- Prewarm sessions for instant response

### Privacy

- All processing on-device by default
- No telemetry or analytics
- Keychain-secured credentials
- Transparent permission requests
- PCC for privacy-preserving cloud inference

### Accessibility

- VoiceOver full support
- Dynamic Type scaling
- Reduce Motion compatibility
- Reduce Transparency fallbacks
- High Contrast mode support
- Voice-first interaction mode

---

## Key Apple Resources

### Documentation

- [Foundation Models Framework](https://developer.apple.com/documentation/FoundationModels)
- [Speech Framework (SpeechAnalyzer)](https://developer.apple.com/documentation/speech)
- [Vision Framework](https://developer.apple.com/documentation/vision)
- [App Intents](https://developer.apple.com/documentation/appintents)
- [Generative AI HIG](https://developer.apple.com/design/human-interface-guidelines/generative-ai)

### WWDC25 Sessions

| Session | Topic |
|---------|-------|
| [286](https://developer.apple.com/videos/play/wwdc2025/286/) | Meet the Foundation Models framework |
| [301](https://developer.apple.com/videos/play/wwdc2025/301/) | Deep dive into the Foundation Models framework |
| [277](https://developer.apple.com/videos/play/wwdc2025/277/) | Bring advanced speech-to-text with SpeechAnalyzer |
| [272](https://developer.apple.com/videos/play/wwdc2025/272/) | Read documents using Vision framework |

### Research

- [Apple Foundation Models 2025 Updates](https://machinelearning.apple.com/research/apple-foundation-models-2025-updates)
- [Apple Intelligence Tech Report 2025](https://machinelearning.apple.com/research/apple-foundation-models-tech-report-2025)

---

## Implementation Priority Matrix

| Priority | Feature | Effort | Impact | Status |
|----------|---------|--------|--------|--------|
| 1 | SpeechAnalyzer upgrade | Medium | High | ✅ Done |
| 2 | Guided Generation (@Generable) | Low | High | ✅ Done |
| 3 | Content Tagging adapter | Low | Medium | ✅ Done |
| 4 | Enhanced Image Understanding | Medium | High | ✅ Done |
| 5 | Inline Siri responses | Medium | Medium | ✅ Done |
| 6 | Document OCR tool | Medium | Medium | ✅ Done |
| 7 | Streaming partial types | Low | Medium | ✅ Done |
| 8 | Private Cloud Compute | High | Medium | ✅ Done |
| 9 | Custom adapter training | High | Low | ⬜ Planned |
| 10 | BNNSGraph audio | Medium | Low | ⬜ Planned |

---

## Platform Support Matrix

| Platform | Status | Minimum Version |
|----------|--------|-----------------|
| iOS | Available | iOS 26.0 |
| macOS | Available | macOS 26.0 |
| iPadOS | Available | iPadOS 26.0 |
| watchOS | Available (companion) | watchOS 26.0 |
| visionOS | Future | visionOS 26.0 |
| CarPlay | Available | iOS 26.0 |

---

Made with ❤️ by [Cameron Rye](https://rye.dev)
