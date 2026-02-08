# Changelog - Clarissa Apple

All notable changes to the Clarissa Apple application will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.2.0] - 2026-02-07

### Added

#### Multi-Turn Tool Chains
- **ToolChain model** — Multi-step workflow data model with `$N.path` argument references for piping outputs between steps
- **ToolChainExecutor** — Sequential execution engine with argument resolution, cancellation support, and progress callbacks
- **Built-in chains** — Travel Prep, Daily Digest, Meeting Context, and Research & Save workflows
- **Chain preview** — ChainPreviewView shows planned steps; users can approve, skip optional steps, or cancel before execution
- **Chain editor** — ToolChainEditorView for creating and editing custom tool chains with step reordering and icon picker
- **Chain persistence** — ToolChainStore actor saves custom chains as JSON in documents directory

#### Shortcuts & Automation
- **Shortcuts actions library** — 8 standalone AppIntents: Get Weather, Get Calendar Events, Create Reminder, Search Contacts, Calculate, Fetch Web Content, Save to Memory, Get Current Location
- **Run Tool Chain action** — Execute any saved tool chain from Shortcuts with optional user input
- **Automation triggers** — AutomationManager with time-of-day, location, and Focus mode trigger conditions
- **FocusModeObserver** — Detects significant time changes to fire time-based automation triggers (iOS)
- **AutomationTriggerStore** — Actor-based persistence for user-configured triggers

#### Smart Notifications
- **NotificationManager** — Full UNUserNotificationCenter integration with 3 categories: check-in, calendar alert, memory reminder
- **Notification actions** — Reply (text input from notification), snooze (1hr), open, and dismiss actions
- **Scheduled check-ins** — ScheduledCheckInStore with per-day scheduling; CheckInScheduler with BGTaskScheduler background execution (iOS)
- **Calendar alerting** — CalendarMonitor scans upcoming events via EventKit, sends "heads up" alerts before meetings with configurable attendee threshold
- **Memory reminders** — MemoryReminderScanner detects time-sensitive patterns (follow-up, this week, by Friday) and surfaces as notifications
- **Share Extension → chains** — SharedResult extended with optional `chainId`; SharedResultBanner shows "Run" button for chain-triggered workflows

#### Settings & UI
- **Automation settings** — New AutomationSettingsView with chain management, check-in scheduling, calendar alert configuration, and memory reminder toggle
- **Settings integration** — Automation tab (macOS) and navigation link (iOS) in SettingsView
- **Chain progress view** — Real-time step-by-step progress display during chain execution

### Changed

- **AgentCallbacks** — Extended with chain lifecycle callbacks: `onChainStart`, `onChainStepStart`, `onChainStepComplete`, `onChainComplete`
- **ChatViewModel** — Integrated tool chain state management, preview flow, and ToolChainCallbacks conformance
- **Schema version** — Bumped to v3 with v2→v3 migration (SharedResult gains optional chainId)
- **ClarissaConstants** — Added tool chain and notification constants

---

## [2.0.0] - 2026-02-06

### Added

#### Smarter Context & Memory

- **Token-budget session trimming** - Replaced hard 100-message limit with token-budget-based trimming that keeps messages until the budget is exceeded, then trims oldest non-system messages
- **Error recovery UX** - Automatic summarization and retry when context window is exceeded, with a "conversation summarized" banner
- **Manual summarize** - "Summarize conversation" button in the context indicator for proactive context management
- **Memory intelligence** - Memories now have category (facts, preferences, routines, relationships), temporal type (permanent, recurring, one-time), confidence scores with decay/boost, and relationship links between related memories
- **Multi-factor relevance ranking** - Memory retrieval weighted by topic (40%), confidence (30%), recency (20%), and category (10%)
- **iCloud conflict resolution** - Timestamp-based merge with `modifiedAt` and `deviceId` fields instead of last-write-wins
- **System prompt budget** - 6-priority budget enforcement (core instructions → summary → memories → proactive context → template → disabled tools) with per-section token caps

#### Conversation UX

- **Edit & Resend** - Long-press any user message to edit and resend from that point
- **Regenerate** - Long-press any assistant message to regenerate the response
- **Undo support** - One-level undo with ephemeral snapshot and banner after edit/regenerate
- **Conversation templates** - 4 bundled templates (Morning Briefing, Meeting Prep, Research Mode, Quick Math) with specialized system prompts, tool sets, and response token hints
- **Custom templates** - Create, edit, and manage your own conversation templates
- **Template picker** - Empty-state grid in chat for quick template selection
- **Conversation search** - Search and filter conversation history by date and topic
- **Proactive intelligence** - Regex-based detection of weather, calendar, and schedule intents with parallel tool prefetch (2s timeout, FM-only, opt-in toggle)

#### Richer Tool Results

- **Expandable weather cards** - Tap to expand hourly/daily forecast with Swift Charts visualization
- **Calendar deep links** - Tap events to open in Calendar.app, tap locations to open in Maps
- **Contact actions** - Tap to call, message, or email directly from contact result cards
- **Web preview cards** - Thumbnail preview with "Open in Browser" button
- **Calculator history** - Copy results to clipboard with confirmation

#### Export & Sharing

- **PDF export** - Export conversations as styled PDF via WKWebView
- **Share as image** - Share individual assistant responses as images (3x ImageRenderer)
- **Code block copy** - Copy code blocks with syntax highlighting from MarkdownContentView

#### Agent Visibility

- **Agent plan preview** - Real-time tool execution plan inferred from tool calls as they happen
- **Live Activity progress** - Dynamic Island shows step-by-step plan progress during multi-tool execution
- **Tool plan view** - Step-by-step progress displayed inline in the chat UI

#### Platform Integration

- **Siri template shortcuts** - Start any bundled template via Siri ("Morning Briefing with Clarissa", etc.)
- **Siri follow-up questions** - 5-minute conversation sessions for back-and-forth with Siri
- **Watch template quick actions** - Morning Briefing and Meeting Prep as watch quick actions
- **Watch template relay** - `templateId` in QueryRequest for Watch→iPhone template passing
- **Share Extension** - Process shared text, URLs, and images via App Group storage
- **Provider fallback banner** - Suggests OpenRouter when Foundation Models fails, with auto-dismiss

#### AI Capabilities

- **SpeechAnalyzer upgrade** - Replaced legacy Speech framework with SpeechAnalyzer for faster, more accurate transcription (15 languages)
- **Guided generation** - `@Generable` structs with `@Guide` annotations for structured output with guaranteed correctness
- **Content tagging** - Topic detection, entity extraction, and emotion/action detection via content tagging adapter
- **Enhanced image understanding** - Foundation Models vision (ViTDet-L encoder) for multimodal image + text reasoning
- **Document OCR** - Full-document text recognition, PDF extraction, handwriting recognition via Vision framework
- **Private Cloud Compute** - Seamless fallback to Apple's privacy-preserving server inference with consent toggle
- **Streaming partial generation** - `PartiallyGenerated` types for progressive UI updates during structured output

### Changed

- **ChatViewModel refactored** - Split from 1164 lines into facade pattern (761 lines) composing ProviderCoordinator, SessionCoordinator, and VoiceController
- **Shared types extracted** - ToolStatus, ThinkingStatus, ChatMessage, and ToolDisplayNames moved to ChatTypes.swift
- **AgentCallbacks** simplified as thin adapter on ChatViewModel updating @Published state + Live Activity

### Technical

- 55+ new unit tests (ProviderCoordinator, SessionCoordinator, ToolDisplayNames, ChatMessage export, context trimming edge cases, Share Extension round-trip, SystemPromptBudget overflow, memory conflict resolution, watch template queries)
- iCloud KVS payload monitoring (warnings at 50KB, errors at 60KB)
- DeviceIdentifier helper (identifierForVendor on iOS, persisted UUID on macOS)
- Token budget overflow logging for future calibration

---

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
