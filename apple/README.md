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
- **Cloud fallback** via OpenRouter API with 100+ model options
- **ReAct agent loop** for multi-step reasoning and tool execution
- **Streaming responses** with real-time token display
- **Session persistence** with automatic title generation
- **Long-term memory** across conversations

### Voice Capabilities

- **SpeechAnalyzer** (iOS 26+) for dramatically faster, more accurate transcription
- **Audio file transcription** using SpeechTranscriber with 15+ language support
- **Legacy fallback** to SFSpeechRecognizer on older devices
- **Text-to-speech** with configurable voice and speed
- **Voice mode** for full hands-free conversation
- **Audio interruption handling** for phone calls, Siri, etc.
- **Bluetooth/headphone support** with proper audio routing

### Tools

- **Calendar** - Create, list, search events (EventKit)
- **Contacts** - Search and view contacts
- **Reminders** - Create, list, complete reminders (EventKit)
- **Weather** - Current conditions and 5-day forecast (WeatherKit)
- **Location** - Get current position with reverse geocoding
- **Web Fetch** - Fetch and parse web content
- **Calculator** - Mathematical expression evaluation
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

### User Interface

- **Liquid Glass design** with iOS 26 glass effects
- **Adaptive navigation** - Tab bar on iPhone, split view on iPad/Mac
- **Tab bar minimization** on scroll for distraction-free reading
- **Glass morphing transitions** between UI states
- **Onboarding flow** with glass-styled buttons
- **Context visualization** with token usage display
- **Tool settings** with enable/disable per tool
- **Haptic feedback** for interactive glass elements
- **Accessibility support** for VoiceOver, Reduce Motion, Reduce Transparency

### Platform Integration

- **Siri Shortcuts** - "Ask Clarissa" and "New Conversation" intents
- **macOS menu bar** - Native keyboard shortcuts (⌘N, ⇧⌘⌫)
- **macOS Settings window** - Standard preferences experience
- **Keychain storage** - Secure API key management
- **Foundation Models prewarming** for faster first response

## Project Structure

```text
apple/Clarissa/
├── Sources/
│   ├── App/           # App entry point and state
│   ├── Agent/         # ReAct agent implementation
│   ├── Camera/        # Camera capture for image analysis (iOS 26+)
│   ├── Intents/       # Siri Shortcuts integration
│   ├── LLM/           # LLM providers, guided generation, content tagging
│   ├── Persistence/   # Session, memory (with auto-tagging), and keychain
│   ├── Tools/         # Tool implementations including DocumentOCR
│   ├── UI/            # SwiftUI views, streaming partial views
│   └── Voice/         # SpeechAnalyzer, SpeechRecognizer, synthesis
├── Resources/         # Info.plist, assets
└── Tests/             # Unit tests
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
