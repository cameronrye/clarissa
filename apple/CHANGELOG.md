# Changelog - Clarissa Apple

All notable changes to the Clarissa Apple application will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-12-12

### Added

#### AI & Conversations

- **Apple Foundation Models integration** - On-device AI with native tool calling
- **OpenRouter cloud fallback** - 100+ model options when on-device AI is unavailable
- **ReAct agent loop** - Multi-step reasoning with tool execution
- **Streaming responses** - Real-time token display during generation
- **Session persistence** - Save and resume conversations with auto-generated titles
- **Long-term memory** - Remember information across conversations
- **Foundation Models prewarming** - Faster first response time

#### Voice Capabilities

- **Speech recognition** - On-device transcription using Speech framework
- **Text-to-speech** - Natural voice output with configurable Siri voices
- **Voice mode** - Full hands-free conversational experience
- **Speech rate control** - Adjustable from slow to very fast
- **Audio session management** - Proper handling of interruptions and device changes
- **Bluetooth support** - Audio routing for headphones and Bluetooth devices

#### Tools

- **Calendar tool** - Create, list, and search calendar events (EventKit)
- **Contacts tool** - Search and view contact information
- **Reminders tool** - Create, list, and complete reminders (EventKit)
- **Weather tool** - Current conditions and 5-day forecast (WeatherKit)
- **Location tool** - Current position with reverse geocoding (CoreLocation)
- **Web fetch tool** - Fetch and parse web content (URLSession)
- **Calculator tool** - Mathematical expression evaluation
- **Remember tool** - Store and retrieve long-term memories
- **Tool settings** - Enable/disable individual tools
- **Foundation Models tool limit** - Intelligent handling of 10-tool maximum

#### User Interface

- **Liquid Glass design** - iOS 26 glass effects throughout the app
- **Adaptive navigation** - Tab bar (iPhone) / Split view (iPad/Mac)
- **Tab bar minimization** - Collapses on scroll for distraction-free reading
- **Glass morphing transitions** - Smooth state transitions between UI elements
- **Onboarding flow** - Welcome screens with Liquid Glass buttons
- **Context visualization** - Token usage display with detailed breakdown
- **Thinking indicator** - Glass-backed animated loading state
- **Haptic feedback** - Tactile response for glass interactions
- **Accessibility support** - VoiceOver, Reduce Motion, Reduce Transparency, High Contrast

#### Platform Integration

- **Siri Shortcuts** - "Ask Clarissa" and "New Conversation" intents
- **macOS menu bar** - Native File and Edit menu commands
- **macOS keyboard shortcuts** - ⌘N (New), ⇧⌘⌫ (Clear), ⌘, (Settings)
- **macOS Settings window** - Standard preferences pane
- **Keychain storage** - Secure API key management

### Technical

- Swift 6.2 with strict concurrency checking
- Swift Package Manager structure with ClarissaKit library
- iOS 26+ and macOS 26+ deployment targets
- Actor-based session and memory management
- Combine publishers for reactive state updates
- OSLog-based logging with privacy annotations

---

Made with ❤️ by [Cameron Rye](https://rye.dev)
