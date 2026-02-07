# Clarissa Apple

Native Apple version of Clarissa for iOS and macOS, built with Swift and SwiftUI, featuring Apple's Liquid Glass design language.

## Requirements

- Xcode 26 beta or later
- iOS 26+ device or simulator
- macOS 26+ (Tahoe) for Mac support
- Apple Silicon device with Apple Intelligence enabled

## Features

### AI & Conversations

- **On-device AI** using Apple Foundation Models with native tool calling
- **Private Cloud Compute** - Seamless fallback to Apple's privacy-preserving server inference with consent toggle
- **Cloud fallback** via OpenRouter API with 100+ model options
- **Provider fallback banner** - Suggests OpenRouter when Foundation Models fails, with auto-dismiss
- **ReAct agent loop** for multi-step reasoning and tool execution
- **Streaming responses** with real-time token display
- **Session persistence** with automatic title generation
- **Long-term memory** with category, temporal type, confidence scoring, and relationship linking
- **Memory intelligence** - Multi-factor relevance ranking (topic 40%, confidence 30%, recency 20%, category 10%)
- **Conversation templates** - 4 bundled templates (Morning Briefing, Meeting Prep, Research Mode, Quick Math) plus custom user-created templates
- **Proactive intelligence** - Automatic detection of weather, calendar, and schedule intents with parallel tool prefetch
- **Edit & Resend** - Long-press any user message to edit and resend from that point
- **Regenerate** - Long-press any assistant message to regenerate the response
- **Error recovery** - Automatic conversation summarization and retry when context window is exceeded
- **Conversation search** - Search and filter conversation history by date and topic

### Voice Capabilities

- **SpeechAnalyzer** (iOS 26+) for dramatically faster, more accurate transcription
- **Audio file transcription** using SpeechTranscriber with 15+ language support
- **Legacy fallback** to SFSpeechRecognizer on older devices
- **Text-to-speech** with configurable voice and speed
- **Voice mode** for full hands-free conversation
- **Audio interruption handling** for phone calls, Siri, etc.
- **Bluetooth/headphone support** with proper audio routing

### Tools

- **Calendar** - Create, list, search events (EventKit) with deep links to Calendar.app and Maps
- **Contacts** - Search and view contacts with tap-to-call, message, or email actions
- **Reminders** - Create, list, complete reminders (EventKit)
- **Weather** - Current conditions and 5-day forecast with expandable hourly/daily charts (WeatherKit + Swift Charts)
- **Location** - Get current position with reverse geocoding
- **Web Fetch** - Fetch and parse web content with preview cards and "Open in Browser"
- **Calculator** - Mathematical expression evaluation with copy-to-clipboard
- **Remember** - Store long-term memories with auto-tagging (iOS 26+)
- **Image Analysis** - OCR, handwriting, object detection, face detection, multi-image comparison
- **Document OCR** - Full-document recognition, PDF extraction, handwriting, table detection (iOS 26+)
- **Document Scanner** - Live camera with auto-detection, corner overlay, perspective correction (iOS 26+)
- **Camera Capture** - Live photo capture for AI image analysis (iOS 26+)

### AI Enhancements (iOS 26+)

- **Guided Generation** - Structured output with `@Generable` for action items, entities, analysis
- **Content Tagging** - Topic detection, emotion analysis, intent classification
- **Streaming Partial UI** - Progressive display of structured results with animations
- **Enhanced Image Understanding** - Foundation Models vision encoder with multi-image reasoning

### Agent Visibility

- **Agent plan preview** - Real-time tool execution plan inferred from tool calls as they happen
- **Live Activity progress** - Dynamic Island shows step-by-step plan progress during multi-tool execution
- **Tool plan view** - Step-by-step progress displayed inline in the chat UI

### Export & Sharing

- **PDF export** - Export conversations as styled PDF
- **Share as image** - Share individual assistant responses as images
- **Code block copy** - Copy code blocks with syntax highlighting
- **Markdown export** - Export conversation history as Markdown

### User Interface

- **Liquid Glass design** with iOS 26 glass effects
- **Adaptive navigation** - Tab bar on iPhone, split view on iPad/Mac
- **Tab bar minimization** on scroll for distraction-free reading
- **Glass morphing transitions** between UI states
- **Template picker** - Empty-state grid for quick template selection
- **Onboarding flow** with glass-styled buttons
- **Context visualization** with token usage display and manual summarize button
- **Tool settings** with enable/disable per tool
- **Haptic feedback** for interactive glass elements
- **Accessibility support** for VoiceOver, Reduce Motion, Reduce Transparency

### Platform Integration

- **Siri Shortcuts** - "Ask Clarissa", "New Conversation", and template shortcuts (Morning Briefing, Meeting Prep, etc.)
- **Siri follow-up questions** - 5-minute conversation sessions for back-and-forth with Siri
- **Share Extension** - Process shared text, URLs, and images from any app
- **Watch companion** - Voice queries, Morning Briefing and Meeting Prep quick actions, WatchConnectivity relay
- **Live Activities** - Dynamic Island and Lock Screen progress during multi-tool execution
- **iCloud sync** - Memory sync with timestamp-based conflict resolution across devices
- **macOS menu bar** - Native keyboard shortcuts (⌘N, ⇧⌘⌫)
- **macOS Settings window** - Standard preferences experience
- **Keychain storage** - Secure API key management
- **Foundation Models prewarming** for faster first response

## Project Structure

```text
apple/Clarissa/
├── Sources/
│   ├── App/              # App entry point and state
│   ├── Agent/            # ReAct agent, proactive context, system prompt budget
│   ├── Camera/           # Camera capture for image analysis (iOS 26+)
│   ├── Extensions/       # Share Extension
│   ├── Intents/          # Siri Shortcuts (Ask, New, Templates)
│   ├── LiveActivity/     # Live Activity attributes + manager
│   ├── LLM/              # LLM providers, guided generation, content tagging
│   ├── Persistence/      # Session, memory (with conflict resolution), keychain
│   ├── Tools/            # Tool implementations including DocumentOCR
│   ├── UI/               # SwiftUI views, coordinators, template editor
│   ├── Voice/            # SpeechAnalyzer, SpeechRecognizer, synthesis
│   └── Watch/            # WatchConnectivity manager, query handler
├── ClarissaWatch/        # watchOS companion app
├── ClarissaWidgets/      # Widget extension
├── Resources/            # Info.plist, assets
└── Tests/                # Unit tests (55+ tests)
```

## Setup

### Option 1: Swift Package (Recommended for development)

1. Open the package in Xcode:

   ```bash
   cd apple/Clarissa
   open Package.swift
   ```

2. Select an iOS 26+ simulator or device

3. Build and run (Cmd+R)

### Option 2: Create Xcode Project

1. Open Xcode and create a new iOS App project

2. Add the package as a local dependency:
   - File > Add Package Dependencies
   - Click "Add Local..."
   - Select the `apple/Clarissa` directory

3. Import and use `ClarissaKit` in your app

## Configuration

### OpenRouter API (Optional)

For cloud LLM fallback when on-device AI is unavailable:

1. Get an API key from [OpenRouter](https://openrouter.ai/keys)
2. Open Settings in the app
3. Enter your API key (stored securely in Keychain)

### Permissions

The app requests the following permissions as needed:

| Permission | Purpose |
| ---------- | ------- |
| **Calendar** | Create and manage calendar events |
| **Contacts** | Search and view contacts |
| **Reminders** | Create and complete reminders |
| **Location** | Get current location for weather and context |
| **Microphone** | Voice input for hands-free mode |
| **Speech Recognition** | Transcribe voice to text |
| **Camera** | Capture photos for AI image analysis |
| **Photo Library** | Analyze images for text, objects, and faces |

## Architecture

### Agent Layer

The agent implements a ReAct (Reasoning + Acting) loop:

1. Receive user message
2. Send to LLM with available tools (limited to 10 for Foundation Models)
3. If LLM requests tool calls, execute them
4. Return tool results to LLM
5. Repeat until LLM provides final response

### LLM Providers

- **FoundationModelsProvider**: Apple's on-device Foundation Models (iOS 26+)
  - Native tool calling with `@Generable` typed arguments
  - Intelligent tool limit handling (max 10 tools)
  - Channel token parsing for clean output
  - Session prewarming for faster first response

- **GuidedGenerationService**: Structured output using guided generation
  - Action item extraction (tasks, events, reminders)
  - Entity extraction (people, places, organizations, dates)
  - Conversation analysis with sentiment and categorization
  - Session title generation

- **ContentTagger**: Specialized content tagging adapter
  - Topic detection and emotion analysis
  - Intent classification with tool suggestions
  - Priority and urgency assessment
  - Auto-tagging for memories

- **OpenRouterProvider**: Cloud fallback using OpenRouter API
  - 100+ model options (Claude, GPT-4, Gemini, Llama, etc.)
  - Secure API key storage in Keychain

### ChatViewModel Architecture (v2.0)

The ChatViewModel uses a facade pattern composing three focused coordinators:

| Component | Responsibility |
|-----------|---------------|
| `ProviderCoordinator` | Provider init, switching, availability, PCC consent |
| `SessionCoordinator` | Session CRUD, switching, title generation, export, share extension handling |
| `VoiceController` | Speech recognition + TTS lifecycle |

### Tool System

Tools are registered with the `ToolRegistry` and implement the `ClarissaTool` protocol:

| Tool | Description | Confirmation Required |
| ---- | ----------- | -------------------- |
| `calendar` | EventKit integration | Yes |
| `contacts` | Contacts framework | No |
| `reminders` | EventKit reminders | Yes |
| `weather` | WeatherKit integration | No |
| `location` | CoreLocation | Yes |
| `web_fetch` | URLSession web fetching | No |
| `calculator` | Math expression evaluation | No |
| `remember` | Long-term memory storage with auto-tagging | No |
| `image_analysis` | Vision + Foundation Models (OCR, classification, faces, AI descriptions) | No |

### Context Management

The agent uses a token-budget-based system (4096 total tokens) with a 6-priority system prompt budget:

| Priority | Content | Max Tokens |
|----------|---------|-----------|
| 1 | Core instructions | ~250 |
| 2 | Conversation summary | ~100 |
| 3 | Memories | ~80 |
| 4 | Proactive context | ~80 |
| 5 | Template prompt | ~50 |
| 6 | Disabled tools list | ~40 |

When the context window is exceeded, the agent automatically summarizes the conversation and retries.

### Voice System

The voice system uses a unified `VoiceManager` that coordinates:

- **SpeechRecognizer**: Unified interface with automatic backend selection
  - **SpeechAnalyzerRecognizer** (iOS 26+): New SpeechAnalyzer API for better accuracy
  - **Legacy fallback**: SFSpeechRecognizer on older devices
- **AudioFileTranscriber**: Transcribe audio files with multi-language support
- **SpeechSynthesizer**: Text-to-speech with configurable Siri voices
- **AudioSessionManager**: Handles audio routing, interruptions, and device changes

### UI Components

Liquid Glass components in `GlassComponents.swift`:

- `ClarissaGlassButton` - Interactive glass icon buttons
- `ClarissaFloatingButton` - Floating action buttons with state
- `ClarissaStateIndicator` - Status display (idle, listening, thinking, speaking)
- `GlassThinkingIndicator` - Animated loading indicator with glass backing
- `AccessibleGlassModifier` - Glass effects with full accessibility support
- `StreamingAnalysisView` - Progressive display of conversation analysis
- `StreamingActionItemsView` - Progressive display of extracted action items
- `FlowLayout` - Flowing tag layout for topics and categories

---

Made with ❤️ by [Cameron Rye](https://rye.dev)
