# Clarissa Roadmap

> Your personal AI assistant — on-device, private, and deeply integrated with Apple platforms

---

## Products

| Product | Status | Description |
|---------|--------|-------------|
| **Clarissa for Apple** | v2.0 shipped | Native iOS, iPadOS, macOS app with Apple Intelligence |
| **Clarissa CLI** | v1.2 shipped | Terminal assistant for developers (TypeScript/Bun) |
| **Clarissa Watch** | v1.0 shipped | watchOS companion target (requires paired iPhone) |
| **Clarissa Widgets** | v1.0 shipped | Home Screen, Lock Screen, Control Center |
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

## Near Term

### v2.1 — Foundations & Core Improvements

Ship quality, testing, and the conversation features that don't depend on new infrastructure.

#### 1. Quality & Foundations

Invest in reliability, accessibility, and resilience before adding more features. This unblocks confident iteration on everything else.

- [ ] **Test coverage expansion** — Unit and integration tests for Agent loop, SessionManager, MemoryManager, and tool execution paths
- [ ] **Data model versioning** — Schema migration strategy for persistence layer as features add new fields (knowledge base, structured memories, full session sync)
- [ ] **Error analytics** — Privacy-respecting on-device metrics: tool failure rates, average ReAct loop iterations, context budget utilization, crash-free session rate
- [ ] **Accessibility pass** — VoiceOver audit, Dynamic Type support in all views, reduced motion alternatives for animations
- [ ] **Offline resilience** — Graceful degradation when offline: cached last-known tool results, queued tool executions, stale-but-useful widget data

#### 2. Conversation Intelligence

v2.0 shipped conversation search/filtering and summarization. Build on that foundation with richer organization and discovery.

- [ ] **Pin messages** — Pin important responses within a conversation for quick reference
- [ ] **Session tagging** — Auto-tag conversations by topic using ContentTagger, plus manual tags
- [ ] **Enhanced session summaries** — Upgrade existing summarization to auto-generate a one-line summary shown in the history list (currently used only for context trimming)
- [ ] **Enhanced cross-session search** — Extend SearchableHistoryView with full-text search across message content, not just session metadata
- [ ] **Favorites** — Star conversations to keep them from being lost in history

#### 3. Home Screen & Lock Screen Widgets

Widgets exist but are static launchers. Make them dynamic and information-rich.

- [ ] **Glanceable morning widget** — Large widget showing today's weather + next event + top reminder, refreshed via timeline provider with intelligent scheduling
- [ ] **Memory spotlight widget** — Medium widget surfacing a relevant memory based on time/location (e.g., "You mentioned wanting to try that restaurant nearby")
- [ ] **StandBy mode card** — Full-screen StandBy display with rotating contextual info (weather, next event, reminders count)

### v2.2 — Tool Chains & Automation

Build the multi-tool engine, then expose it through Shortcuts, notifications, and extensions.

#### 4. Multi-Turn Tool Chains

The ReAct loop executes tools one at a time. Let the agent compose richer workflows. This is foundational infrastructure — tool chains power the Shortcuts actions library, scheduled check-ins, and template quick actions.

- [ ] **Dependent tool chaining** — Agent can declare tool dependencies so outputs pipe into inputs (e.g., "get today's calendar → find contacts for attendees → fetch weather for meeting location")
- [ ] **Tool chain templates** — Saveable multi-tool workflows that users can trigger with one tap (e.g., "Travel prep: weather + calendar + reminders for trip dates")
- [ ] **Chain preview** — Show the planned tool chain before execution and let users approve, edit, or skip steps

#### 5. Shortcuts & Automation Power-Ups

Clarissa already has Siri Shortcuts, but they're one-shot. Make Clarissa a first-class automation citizen. *Depends on #4 for tool chain execution.*

- [ ] **Shortcuts actions library** — Expose individual tools (weather, calendar, reminders, web fetch) as standalone Shortcuts actions so users can chain them in their own automations without a chat prompt
- [ ] **Automation triggers** — Register for time-of-day, location, and Focus mode triggers via the Intents framework to proactively surface information (e.g., commute weather at 7:30am)
- [ ] **Shortcut result types** — Return rich `IntentResult` types (not just strings) so Shortcuts can pass structured data between actions
- [ ] **Action extensions** — "Ask Clarissa" action extension in Safari, Notes, Mail for contextual queries without switching apps

#### 6. Smart Notifications

Clarissa is purely reactive today. Add a lightweight notification layer. Scheduled check-ins extend the existing Watch template system (Morning Briefing, Meeting Prep) — notifications become the delivery mechanism for templates that already exist. *Depends on #4 for background tool chain execution.*

- [ ] **Scheduled check-ins** — User-configured schedules that trigger existing templates (Morning Briefing, Meeting Prep, or custom) in the background and deliver results as a notification
- [ ] **Calendar alerting** — "Heads up: your 2pm meeting has 6 attendees you haven't met — want a prep?" 30 min before events with new contacts
- [ ] **Memory reminders** — Surface time-sensitive memories as notifications (e.g., "You wanted to follow up with Alex this week")
- [ ] **Notification actions** — Reply, snooze, or expand directly from the notification
- [ ] **Share Extension → tool chains** — Extend the existing Share Extension to trigger tool chain workflows (e.g., share a URL → auto-summarize → save to Notes)

---

## Medium Term

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
| 1 | Quality & Foundations | Low | High | — | Near (v2.1) |
| 2 | Conversation Intelligence | Low | Medium | — | Near (v2.1) |
| 3 | Dynamic Widgets | Low | High | — | Near (v2.1) |
| 4 | Multi-Turn Tool Chains | Medium | High | #1 (tests) | Near (v2.2) |
| 5 | Shortcuts & Automation | Medium | High | #4 | Near (v2.2) |
| 6 | Smart Notifications | Medium | High | #4 | Near (v2.2) |
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
