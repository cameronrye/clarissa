# Clarissa Roadmap

> Your personal AI assistant — on-device, private, and deeply integrated with Apple platforms

---

## Products

| Product | Status | Description |
|---------|--------|-------------|
| **Clarissa for Apple** | v2.2 shipped | Native iOS, iPadOS, macOS app with Apple Intelligence |
| **Clarissa CLI** | v1.2 shipped | Terminal assistant for developers (TypeScript/Bun) |
| **Clarissa Watch** | v1.0 shipped | watchOS companion target (requires paired iPhone) |
| **Clarissa Widgets** | v2.0 shipped | Home Screen, Lock Screen, Control Center, StandBy |
| **clarissa.run** | Live | Documentation and marketing site (Astro) |

---

## Shipped in v2.0

For context on the baseline these roadmap items build on:

- Memory dedup & relevance ranking (Levenshtein distance, topic-based scoring)
- Priority-based context trimming & conversation summarization
- Conversation search & filtering (SearchableHistoryView with date/topic filters)
- Siri follow-up questions (SiriConversationSession, 5-min expiry)
- Private Cloud Compute integration (consent toggle, error handling)
- Live Activities (multi-tool execution progress, Dynamic Island)
- Share Extension (text/URL/image processing via App Group)
- System prompt budget enforcement (6-priority tiers, per-section caps)
- iCloud conflict resolution (timestamp-based merge, device ID tracking)
- Watch template quick actions (Morning Briefing, Meeting Prep)
- Provider fallback banner (suggests OpenRouter on Foundation Models failure)

---

## Shipped in v2.1

Quality, testing, conversation intelligence, and dynamic widgets.

### 1. Quality & Foundations

- [x] **Test coverage expansion** — Unit and integration tests for Agent loop (6 tests), SessionManager (38 tests across 6 suites), MemoryManager, and tool execution paths
- [x] **Data model versioning** — SchemaVersion enum with SchemaMigrator pipeline; versioned PersistedSessionData with sequential migration support
- [x] **Error analytics** — On-device AnalyticsCollector actor: tool failure rates, avg ReAct iterations, context utilization, crash-free session rate; displayed in Settings → Diagnostics
- [x] **Accessibility pass** — VoiceOver labels/hints on all interactive elements, `.accessibilityElement(children: .combine)` on message bubbles and session rows, Dynamic Type via `@ScaledMetric`
- [x] **Offline resilience** — OfflineManager with NWPathMonitor, cached tool results with staleness threshold, offline UI banner, stale widget data indicators

### 2. Conversation Intelligence

- [x] **Pin messages** — Pin/unpin via context menu, PinnedMessagesStrip above message list, isPinned field on Message
- [x] **Session tagging** — Manual tags CRUD on sessions, merged with auto-detected topics for unified filter chips
- [x] **Enhanced session summaries** — SessionSummarizer using content tagging adapter, auto-generates one-line summary shown in history list
- [x] **Enhanced cross-session search** — SearchableHistoryView extended to match summaries, manual tags, and full message content
- [x] **Favorites** — Star sessions via swipe action, favorites filter toggle, favorited sessions exempt from trimming

### 3. Home Screen & Lock Screen Widgets

- [x] **Glanceable morning widget** — Large widget with weather + next event + top reminder via MorningDataCollector, intelligent timeline scheduling
- [x] **Memory spotlight widget** — Medium widget surfacing contextual memories scored by confidence, time-of-day relevance, and recency
- [x] **StandBy mode card** — Full-screen StandBy display with rotating contextual info (weather, next event, reminders count)

---

## Shipped in v2.2

Tool chains, automation, and smart notifications.

### 4. Multi-Turn Tool Chains

- [x] **Dependent tool chaining** — ToolChainExecutor pipes outputs into inputs via `$N.path` argument references (e.g., "get today's calendar → find contacts for attendees → fetch weather for meeting location")
- [x] **Tool chain templates** — Saveable multi-tool workflows (built-in: Travel Prep, Daily Digest, Meeting Context, Research & Save) plus custom chain editor
- [x] **Chain preview** — ChainPreviewView shows planned steps before execution; users can approve, skip optional steps, or cancel

### 5. Shortcuts & Automation Power-Ups

- [x] **Shortcuts actions library** — 8 standalone Shortcuts actions (Get Weather, Get Calendar, Create Reminder, Search Contacts, Calculate, Fetch Web, Save to Memory, Get Location) plus Run Tool Chain action
- [x] **Automation triggers** — AutomationManager with time-of-day, location, and Focus mode trigger conditions; FocusModeObserver for significant time change detection
- [x] **Shortcut result types** — All Shortcuts actions return `ReturnsValue<String>` for structured data passing between actions
- [x] **Action extensions** — Share Extension extended to trigger tool chain workflows via optional `chainId` on SharedResult

### 6. Smart Notifications

- [x] **Scheduled check-ins** — ScheduledCheckInStore with per-day scheduling, BGTaskScheduler background execution, delivers results as actionable notifications
- [x] **Calendar alerting** — CalendarMonitor scans upcoming events via EventKit, alerts before meetings with configurable attendee threshold and lead time
- [x] **Memory reminders** — MemoryReminderScanner detects time-sensitive patterns ("follow up this week", "by Friday") and surfaces as notifications
- [x] **Notification actions** — Reply (text input), snooze (1hr), open, and dismiss actions on all notification categories
- [x] **Share Extension → tool chains** — SharedResult gains optional `chainId` field; SharedResultBanner shows "Run" button to trigger chain with shared content as input

---

## Near Term

### 7. Focus Mode Integration

Adapt behavior based on the user's current Focus mode.

- [ ] **Focus-aware responses** — Detect active Focus mode (Work, Personal, Sleep, etc.) and adjust system prompt tone and tool selection accordingly
- [ ] **Do Not Disturb handling** — Suppress voice output and haptics when DND is active
- [ ] **Focus-based templates** — Auto-suggest relevant conversation templates based on active Focus (e.g., Work Focus → Meeting Prep, Morning Focus → Morning Briefing)

### 8. Health & Fitness Integration

Apple Health is a rich data source that no third-party AI assistant taps into well.

- [ ] **HealthKit tool** — Read health data (steps, sleep, heart rate, workouts) with proper authorization
- [ ] **Wellness check-in** — "How am I doing this week?" queries that summarize health trends
- [ ] **Workout context** — Include recent activity data in morning briefings and proactive context
- [ ] **Sleep-aware responses** — Factor sleep data into response timing suggestions ("You slept 5 hours — maybe reschedule that early meeting?"). *Depends on #6 (Smart Notifications) for proactive delivery.*

### 9. Apple Intelligence Adapters

Train custom adapters using Apple's adapter training toolkit to teach the on-device model Clarissa-specific behaviors. *Blocked on toolkit availability — announced at WWDC25 but not yet publicly shipped.* In the interim, invest in prompt engineering and few-shot examples within the system prompt budget to approximate these behaviors.

- [ ] **Conversation style adapter** — Train on Clarissa's ideal response style (concise, actionable, personal) to improve baseline response quality
- [ ] **Memory extraction adapter** — Specialized adapter that identifies facts worth remembering from conversations without being explicitly told
- [ ] **Tool selection adapter** — Improve the model's ability to pick the right tool and compose arguments accurately, reducing retry loops

### 10. Music & Media Control

Extend Clarissa's tool set to control media playback.

- [ ] **MusicKit tool** — Play songs, playlists, and albums via MusicKit; search Apple Music catalog
- [ ] **Now Playing context** — Include currently playing track in proactive context for music-aware responses
- [ ] **Podcast recommendations** — Suggest podcasts based on conversation topics and interests stored in memory

### 11. Notes & Documents

Bridge the gap between conversations and long-form content.

- [ ] **Notes tool** — Create, append to, and search Apple Notes via the Notes framework
- [ ] **Save to Notes** — One-tap action to save any assistant response as a formatted Apple Note
- [ ] **PDF summarization** — Drag and drop a PDF into chat for on-device summarization via Vision + Foundation Models
- [ ] **Clipboard awareness** — Detect rich clipboard content (URLs, text, images) and offer to act on it when the user starts a conversation

### 12. iPad Experience

iPad is a first-class target but currently gets the iPhone layout. Take advantage of the larger canvas.

- [ ] **Stage Manager & Split View** — Proper multitasking support with resizable windows and side-by-side use
- [ ] **Multi-column layout** — Session list + conversation side-by-side on wider screens
- [ ] **Apple Pencil input** — Handwriting recognition for chat input via PencilKit

---

## Long Term

### 13. Multi-Device Continuity

Clarissa runs on iPhone, iPad, Mac, and Watch but they're largely independent.

- [ ] **Handoff support** — Start a conversation on iPhone, continue on Mac (or vice versa) via Handoff
- [ ] **Universal clipboard integration** — Share context between devices seamlessly
- [ ] **Sync conversation history** — Move beyond iCloud KVS for memories to full session sync via CloudKit or SwiftData + CKSyncEngine

### 14. Cross-Device Processing

Route complex queries from Watch/iPhone to Mac's more powerful hardware when on the same network. This is architecturally distinct from Continuity — it requires custom service discovery, query routing, and fallback handling rather than system-level APIs.

- [ ] **Local network discovery** — Discover Mac instances on the local network via Bonjour
- [ ] **Query routing** — Offload expensive tool chains or long-context queries to Mac
- [ ] **Graceful fallback** — Seamlessly fall back to on-device processing when Mac is unavailable

### 15. visionOS

- [ ] **Spatial chat interface** — Floating glass conversation window with depth
- [ ] **Environment awareness** — Use room scanning context for relevant responses
- [ ] **Volumetric tool results** — 3D weather visualizations, spatial calendar views

### 16. On-Device Knowledge Base

Go beyond ephemeral conversations with a persistent, searchable knowledge layer. This is the highest-complexity initiative on the roadmap — Local RAG depends on either Apple shipping an embedding model in Foundation Models or bundling a lightweight model.

- [ ] **Auto-digest** — Automatically distill key facts from every conversation into a personal knowledge base (distinct from memories — structured facts vs. preferences)
- [ ] **Topic graphs** — Visualize connections between topics discussed across conversations
- [ ] **Local RAG** — Index the knowledge base for retrieval-augmented generation, giving Clarissa long-term recall without growing the context window
- [ ] **Export to Obsidian/Apple Notes** — Sync the knowledge base to external note systems

### 17. Third-Party Integrations via App Intents

Leverage iOS 26's expanded App Intents ecosystem to interact with third-party apps.

- [ ] **App Intent discovery** — Discover and call App Intents exposed by other installed apps (Todoist, Things, Fantastical, etc.)
- [ ] **Smart home control** — HomeKit scenes and device control via natural language
- [ ] **Transportation** — Transit directions, ride sharing status, flight tracking via relevant app intents
- [ ] **Custom integrations** — Let power users define custom tool → App Intent mappings in Settings

### 18. CLI v2

The CLI tool has been stable at v1.2. Bring it forward with the learnings from the Apple app.

- [ ] **Shared memory layer** — Sync memories between CLI and Apple app via iCloud
- [ ] **MCP server mode** — Run Clarissa CLI as an MCP server so other tools (VS Code, Cursor, etc.) can use its tools
- [ ] **Agent workflows** — Define reusable multi-step workflows in YAML that the CLI agent executes
- [ ] **Interactive TUI overhaul** — Modernize the terminal UI with better streaming, collapsible tool output, and inline images (iTerm2/Kitty)

---

## Priority Matrix

| # | Feature | Effort | Impact | Dependencies | Timeline |
| --- | --- | --- | --- | --- | --- |
| 1 | Quality & Foundations | Low | High | — | **Shipped (v2.1)** |
| 2 | Conversation Intelligence | Low | Medium | — | **Shipped (v2.1)** |
| 3 | Dynamic Widgets | Low | High | — | **Shipped (v2.1)** |
| 4 | Multi-Turn Tool Chains | Medium | High | #1 (tests) | **Shipped (v2.2)** |
| 5 | Shortcuts & Automation | Medium | High | #4 | **Shipped (v2.2)** |
| 6 | Smart Notifications | Medium | High | #4 | **Shipped (v2.2)** |
| 7 | Focus Mode Integration | Low | Medium | — | Medium |
| 8 | Health & Fitness | Medium | High | #6 (notifications) | Medium |
| 9 | Apple Intelligence Adapters | High | High | Apple toolkit | Medium |
| 10 | Music & Media | Medium | Medium | — | Medium |
| 11 | Notes & Documents | Medium | Medium | — | Medium |
| 12 | iPad Experience | Low | Medium | — | Medium |
| 13 | Multi-Device Continuity | High | High | — | Long |
| 14 | Cross-Device Processing | High | Medium | #13 | Long |
| 15 | visionOS | High | Medium | — | Long |
| 16 | On-Device Knowledge Base | Very High | High | Embedding model | Long |
| 17 | Third-Party App Intents | Medium | High | — | Long |
| 18 | CLI v2 | Medium | Medium | — | Long |

---

Made with ❤️ by [Cameron Rye](https://rye.dev)
