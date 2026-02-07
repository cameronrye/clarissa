# Clarissa v2.0 Roadmap

> Next-generation features for Clarissa — smarter context, better architecture, richer UX

---

## v1 Review Summary

### Strengths

- Clean actor-based architecture with proper `Sendable` concurrency
- Smart context management with priority trimming and summarization for tight 4096-token budget
- Multi-source memory sync (iCloud + Keychain + CLI) with semantic deduplication
- Full accessibility and iOS 26 Liquid Glass design
- Zero external dependencies — all Apple frameworks
- Comprehensive Siri integration with inline responses and follow-ups
- 9 native tools with `@Generable` Apple Intelligence bridges and proper permission handling
- Solid test foundation: `MockLLMProvider`, Agent, Memory, Session, Voice, and WatchConnectivity tests (~3,900 lines)
- Feature-complete watchOS companion with voice input, quick actions, complications, and WatchConnectivity

### Known Weaknesses

- Token estimation is character-based (~0.25 tokens/char) — drifts on mixed-language or code-heavy input
- Last-write-wins iCloud sync with no conflict resolution
- `ChatViewModel` is 1164 lines doing too much (session mgmt, voice, shortcuts, streaming, provider switching)
- Test coverage gaps: provider switching, context trimming edge cases, Share Extension flow, new extracted components
- 100-message session limit can still blow past the token budget since messages vary wildly in length

---

## P0 — Foundation (Do First)

### 1. Break Up ChatViewModel

Split `ChatViewModel.swift` (1164 lines) into focused, testable components.

**Current problems:**
- Session management, voice control, shortcuts, streaming, and provider switching all in one file
- Hard to test any single behavior in isolation
- Changes in one area risk regressions in another

**Proposed split:**

| Component | Responsibility | Est. lines extracted |
|-----------|---------------|---------------------|
| `ProviderCoordinator` | Provider init, switching, availability, PCC consent | ~280 |
| `SessionCoordinator` | Session CRUD, switching, title generation, share extension handling | ~285 |
| `VoiceController` | Speech recognition + TTS lifecycle | ~60 |
| Agent (inline callbacks) | Move `AgentCallbacks` to Agent or a thin adapter instead of standalone controller | ~95 |

Each becomes a small `@Observable` or actor that the view model composes. `ShortcutRouter` is small enough to fold into `SessionCoordinator` since shortcuts mostly just start sessions with specific configs.

- [x] Extract `ProviderCoordinator` from ChatViewModel → `ProviderCoordinator.swift` (~110 lines)
- [x] Extract `SessionCoordinator` from ChatViewModel → `SessionCoordinator.swift` (~165 lines)
- [x] Extract `VoiceController` from ChatViewModel → `VoiceController.swift` (~90 lines)
- [x] Move shared types to `ChatTypes.swift` (ToolStatus, ThinkingStatus, ChatMessage, ToolDisplayNames)
- [x] AgentCallbacks stays on ChatViewModel as thin adapter (callbacks update @Published state + Live Activity)
- [x] Verify build compiles successfully (zero new errors)
- [x] Slim ChatViewModel to 761 lines (facade pattern composing 3 coordinators)
- [ ] Verify all UI bindings still work at runtime (build-verified, **needs device smoke test before release**)

---

### 2. Expand Test Coverage

Build on the existing test suite (`ClarissaTests.swift`, `FoundationTests.swift`, `VoiceTests.swift`, `WatchConnectivityTests.swift`) to cover gaps revealed by the ChatViewModel refactor and known weak spots.

**Existing coverage:**

| Area | Status |
|------|--------|
| Agent ReAct loop | Covered — tool execution, retry, refusal, trimming |
| Memory dedup/ranking | Covered |
| Session limits/titles | Covered |
| Voice manager | Covered |
| WatchConnectivity messages | Covered |

**Gaps to fill:**

| Area | What to Test |
|------|-------------|
| ProviderCoordinator | Provider switching, availability fallback, PCC consent flow |
| SessionCoordinator | Session switching, title generation, share extension import |
| Context trimming edge cases | Mixed-length messages, tool-heavy conversations, summary generation |
| Share Extension | Text/URL/image processing, App Group storage round-trip |
| New extracted components | Each new coordinator/controller gets unit tests alongside extraction |

- [x] Add ProviderCoordinator tests (formatModelName, availability, PCC consent) — 4 tests
- [x] Add SessionCoordinator tests (exportConversation, buildSharedResultMessage) — 6 tests
- [x] Add ToolDisplayNames tests (all known tools, snake_case fallback, edge cases) — 4 tests
- [x] Add ChatMessage export tests (toMarkdown for all roles, image data) — 8 tests
- [x] Verify existing tests still pass after ChatViewModel refactor
- [x] Add context trimming edge case tests (mixed-length, tool-heavy, CJK, multi-role) — 4 tests
- [x] Add Share Extension round-trip tests (text/URL/image encode-decode, ordering, empty array) — 5 tests

---

## P1 — Core UX Improvements

### 3. Smarter Token Budgeting

Replace character-based estimation with calibrated token counting.

**Current approach:** `characterCount / 4` for Latin, `characterCount` for CJK — inaccurate for code, mixed content, tool results.

**Proposed improvements:**
- Investigate Foundation Models response metadata for actual token counts (note: `LanguageModelSession` response objects may not expose token usage metadata like OpenAI's API — plan for this investigation to come back empty)
- Build a calibration table: track actual vs estimated over time, auto-correct the ratio per content type
- Use `NaturalLanguage.NLTokenizer` as a *word-level* heuristic (note: NLTokenizer counts linguistic words, not BPE subwords — it's better than character-based but wildly inaccurate for code/JSON, e.g., `{"key":"value"}` = 1 NLTokenizer word but ~7 BPE tokens)
- Even without FM metadata, calibrate by tracking when `contextWindowExceeded` errors fire — that provides a ground truth signal for tuning the estimation ratio
- **Primary win:** Switch from hard 100-message limit (`ClarissaConstants.maxMessagesPerSession`) to **token-budget-based limit** — keep adding messages until budget is exceeded, then trim oldest non-system messages

- [x] Replace message-count limit with token-budget limit (SessionManager now uses TokenBudget-based trimming with hard cap safety net)
- [x] Log token estimates on contextWindowExceeded for future calibration data
- ~Investigate FM response token count metadata~ — deferred (FM API unlikely to expose this)
- ~Implement calibration loop~ — deferred (character-based estimation sufficient for v2)
- ~Update context indicator UI to show real token usage~ — deferred (current estimate adequate)

---

### 4. Edit & Regenerate

Let users edit their last message or regenerate the assistant's last response — a lightweight alternative to full conversation branching that covers the most common recovery case.

**Design:**
- Long-press user message → "Edit & Resend": truncates conversation to that point, opens editor, resends
- Long-press assistant message → "Regenerate": re-runs the agent turn with the same input
- No tree structure needed — simply replaces messages from the edit point forward
- Preserves session linearity for context trimming, export, and Siri follow-ups

**Why:** The 4096-token window means users frequently hit dead ends. Edit & Regenerate lets them recover without starting over, and without the complexity of a full branching system.

- [x] Add "Edit & Resend" action on user message long-press (context menu in ChatView)
- [x] Add "Regenerate" action on assistant message long-press (context menu in ChatView)
- [x] Implement conversation truncation from edit point (`editAndResend`, `regenerateResponse` in ChatViewModel)
- [x] Sync agent message history after truncation (`syncAgentMessages`)
- [x] Add undo support (ephemeral `undoSnapshot`, one level, with undo banner in chat UI)

---

### 5. Error Recovery UX

The 4096-token limit means `contextWindowExceeded` errors are inevitable in longer conversations. Add graceful automatic recovery instead of just surfacing the error.

**Why P1:** With only 1996 tokens for history, context overflow is a *core* UX issue, not an edge case. The summarization infrastructure already exists in `Agent.swift` (`summarizeOldMessages`) — wiring it into error recovery is low effort, high impact.

**Flow:**
1. Agent catches `contextWindowExceeded` error
2. Automatically summarize the conversation so far (using the existing `summarizeOldMessages` infrastructure or a dedicated summarization prompt)
3. Replace history with summary + last 2–3 messages
4. Retry the failed request with the compressed context
5. Show a subtle banner: "Context was getting long — I summarized our conversation to continue"

- [x] Detect `contextWindowExceeded` in sendMessage error handler (ChatViewModel)
- [x] Add `aggressiveTrim()` to Agent — forces summarization + keeps only last 2 messages + resets provider session
- [x] Auto-retry failed request with compressed context after trim
- [x] Add "conversation summarized" banner in chat UI (auto-dismisses after 5s)
- [x] Add manual "Summarize conversation" button in context indicator (ContextDetailSheet button + ChatViewModel.manualSummarize())

---

### 6. Proactive Intelligence (Agent-Initiated Context)

Add a background analysis pass that prefetches context before the agent responds. Start narrow with explicit pattern matching, expand later.

**Phase 1 — Pattern-Based Prefetch (ship first):**
1. User sends a message
2. Regex detectors scan for explicit signals:
   - Time/date patterns ("at 3", "tomorrow", "next Tuesday") → prefetch calendar
   - Weather keywords ("cold", "rain", "weather") → prefetch weather
   - Contact names (matched against Contacts framework) → prefetch contact info
3. Prefetched data injected as system context for the agent turn

**Phase 2 — ContentTagger Intent Classification (iterate later):**
- Use ContentTagger for broader topic detection
- Expand to implicit intents beyond keyword matching

**Guardrails:**
- Only activate when FM is the active provider (free, on-device) to avoid burning API calls
- Gate behind a user setting ("Proactive Context" toggle in Settings) — **defaults to OFF** to avoid App Store review friction around proactive data access
- Prefetch timeout: 2 seconds max, agent proceeds without prefetch data if slow
- **Hard token cap: 100 tokens max for all prefetched context combined** — prefer terse summaries ("3 events today, next at 2pm: Team Standup") over full tool output to avoid eating into the already-tight 1996-token history budget

**App Store compliance:**
- All target tools (Calendar, Contacts, Weather) already handle their own permission requests
- Data stays on-device when FM is active
- Privacy policy must be updated to cover proactive data access
- Opt-in toggle satisfies Guideline 5.1.1 (Data Collection and Storage)

- [x] Implement regex-based intent detectors (weather keywords → weather tool, time/schedule patterns → calendar tool)
- [x] Add parallel tool prefetch for detected intents (2s timeout via TaskGroup)
- [x] Inject prefetched context into agent system prompt (capped at ~100 tokens / 400 chars)
- [x] Add "Proactive Context" toggle in Settings (iOS + macOS sections) — default OFF
- [x] Gate behind FM-only check (only activates when Foundation Models is active provider)
- [x] Add subtle UI indicator when proactive data is available (proactive label capsules on assistant messages)
- [x] Update privacy policy to cover proactive context access
- ~Phase 2: Expand to ContentTagger-based detection~ — deferred to v2.1 (regex detection covers high-value cases)

---

### 7. Conversation Templates / Quick Actions

Pre-built conversation starters with specialized system prompts, pre-enabled tools, and response tuning.

**Templates:**

| Template | Tools | System Prompt Focus | Response Hint |
|----------|-------|-------------------|---------------|
| Morning Briefing | Weather + Calendar + Reminders | Summarize day ahead | Medium |
| Meeting Prep | Calendar + Contacts | Event details + attendee info | Medium |
| Research Mode | Web Fetch + Remember | Longer responses, save findings | Long |
| Quick Math | Calculator | Minimal context, fast answers | Short |

**Implementation:**
- Store templates as JSON in app bundle with `maxResponseTokens` hint per template
- Make `FoundationModelsProvider` accept per-request `maxResponseTokens` (currently hardcoded at 400 in `ClarissaConstants.foundationModelsMaxResponseTokens`) so templates can override it
- Surface as widget actions, Siri shortcuts, and watch quick actions
- Users can create custom templates
- Good for App Store review — demonstrates clear, differentiated functionality beyond a generic chat wrapper

- [x] Define template JSON schema (tools, system prompt, response hint) — `ConversationTemplate` struct
- [x] Create bundled default templates (Morning Briefing, Meeting Prep, Research Mode, Quick Math)
- [x] Make `foundationModelsMaxResponseTokens` configurable per-request in `FoundationModelsProvider` + `OpenRouterProvider`
- [x] Add template picker UI (EmptyStateView grid in ChatView)
- [x] Wire templates to system prompt + tool configuration + response token hint (`Agent.applyTemplate`)
- [x] Add Siri shortcuts for each default template (StartTemplateIntent + 4 AppShortcut entries with phrases)
- ~Surface templates as watch quick actions~ — done via Watch Architecture (#15)
- [x] Allow user-created custom templates (TemplateStore actor, TemplateEditorView, CustomTemplateListView in Settings)

---

## P2 — Polish & Depth

### 8. Richer Tool Results

Upgrade tool result cards from static JSON to interactive SwiftUI views.

**Enhancements:**

| Tool | Improvement |
|------|-----------|
| Weather | Tap to expand hourly/daily forecast, mini chart |
| Calendar | Tap to open in Calendar.app, show map for event location |
| Contacts | Tap to call/message directly from result card |
| Web Fetch | Show preview image + summary, tap to open Safari |
| Calculator | Calculation history, tap to reuse previous expressions |

- [x] Design interactive result card components
- ~Migrate tool results to `@Generable` structs for structured output~ — dropped (manual parsing robust, token cost not justified)
- [x] Implement expandable weather card with chart (Swift Charts ForecastChartView)
- [x] Add deep links from calendar/contact cards to system apps (calshow:, maps://, tel:, sms:, mailto:)
- [x] Add web preview cards with thumbnail (Open in Browser button)
- [x] Add calculation history with reuse (copy-to-clipboard with confirmation)

---

### 9. Conversation Branching (Full)

Upgrade Edit & Regenerate (P1 #4) to full tree-based branching — only if user feedback shows the lightweight version isn't sufficient.

**Design:**
- Add `parentMessageId` field to `Message` to create a tree structure
- Users can tap any message to edit and branch from that point
- Branch history preserved — swipe between branches
- Session storage updated to persist tree structure

**Cascading changes required:**
- Context trimming must walk tree paths, not flat arrays
- Session export must linearize selected branch
- Siri follow-ups must track which branch is active
- Live Activities must reference current branch
- Watch response display must pick correct branch

**Migration:** Adding `parentMessageId` to `Message` is a breaking change for persisted sessions. The current `Session` model stores a flat `[Message]` array — moving to a tree structure changes the serialization format. Requires a migration path for existing JSON session files (add fields as optional with nil defaults, interpret nil as "linear/no branching").

- [ ] Add `parentMessageId` and `branchIndex` to Message model (optional fields for backward compat)
- [ ] Add session data migration for existing flat-array sessions
- [ ] Update SessionManager to persist message trees
- [ ] Update context trimming to walk tree paths
- [ ] Add branch navigation UI (swipe between siblings)
- [ ] Update export, Siri, Live Activity, and Watch to handle branches

---

### 10. Memory Intelligence

Upgrade from flat key-value memories to a structured, temporal memory system.

**New memory model:**

| Field | Purpose |
|-------|---------|
| Category | Facts, preferences, routines, relationships |
| Temporal type | Permanent vs recurring vs one-time |
| Confidence | Decays if unused, increases on access |
| Relationships | Links between related memories |

**Behaviors:**
- "Cameron usually runs on Tuesdays" tagged as `routine` with weekly recurrence
- Frequently-used memories stay high-confidence; unused ones decay and get suggested for cleanup
- Related memories linked (e.g., "Cameron's wife" ↔ "anniversary date")
- Relevance ranker weights category + temporal relevance, not just topic overlap

**Implementation considerations:**
- **Confidence decay timing:** Decay on access (when `getForPrompt` / `getRelevantForConversation` runs), not on a background timer — avoids needing a background process
- **Relationships as flat references:** Store relationship links as `[UUID]` arrays on each memory rather than a separate graph store. This keeps the flat Keychain/iCloud KVS storage model intact
- **iCloud KVS storage limit:** NSUbiquitousKeyValueStore has a 1MB total limit. Adding category, temporalType, confidence, and relationships increases payload by ~50-100 bytes per memory. With 100 memories this is manageable (~5-10KB overhead), but monitor total payload size
- **Consider SwiftData migration** only if relationship queries become complex enough to warrant it — premature for v2.0

- [x] Extend memory model with category, temporal type, confidence, relationships (as optional fields for backward compat)
- [x] Implement confidence decay/boost logic (on-access, not background timer)
- [x] Add memory relationship linking (flat UUID references)
- [x] Update relevance ranker to use new fields (multi-factor: topic 40% + confidence 30% + recency 20% + category 10%)
- [x] Update Memory Review UI for categories and relationships (badges, confidence %, link count)
- [x] Add iCloud KVS payload size monitoring (warnings at 50KB, errors at 60KB)

---

### 11. Agent Plan Preview

Surface the agent's multi-tool execution plan to users during execution. The ReAct loop already chains tool calls — this is about **visibility**, not a new execution model.

**Approach: Infer plans from tool calls, don't generate them.**

Asking the on-device FM model to reliably emit structured plan summaries is unreliable within the tight token budget. Instead, infer the plan retroactively from tool calls as they happen:

1. Agent begins processing — Live Activity shows "Thinking..."
2. First tool fires (e.g., Calendar) — Live Activity updates to show "Checking your calendar..."
3. Second tool fires (e.g., Weather) — step 1 marked complete, step 2 shown as active
4. Response complete — all steps marked done

This is simpler, more reliable, costs zero prompt tokens, and provides the same UX value.

**Optional enhancement:** For the plan approval flow, use a lightweight heuristic (e.g., if >2 tools will be called based on regex/keyword detection from Proactive Intelligence #6) to show a preview *before* execution.

- [x] Map tool names to human-readable step descriptions (ToolDisplayNames.format, PlanStep model)
- [x] Update Live Activity to show inferred plan steps with real-time progress (planStepNames in ContentState)
- [x] Add step-by-step progress view in chat UI (ToolPlanView between messages and typing bubble)
- ~Optional: Add plan approval UI using Proactive Intelligence detectors~ — dropped (inferred plan preview sufficient)

---

### 12. Export & Sharing

Extend the existing Markdown export (`SessionCoordinator` after P0 refactor) with richer sharing options.

**Already implemented:** `conversationExport` generates Markdown text.

**New:**
- [x] Add PDF export via `WKWebView.createPDF()` (styled HTML with inline CSS, SessionCoordinator)
- [x] Share a specific response as image (MessageImageRenderer + SwiftUI ImageRenderer at 3x)
- [x] Copy code blocks with syntax highlighting (MarkdownContentView + CodeBlockView with copy button)
- [x] Add share button to message long-press menu (Share as Image on assistant messages)
- ~Add email sharing via dedicated button~ — dropped (standard Share sheet already surfaces Mail)

---

## P3 — Nice to Have

### 13. iCloud Conflict Resolution

Replace last-write-wins with timestamp-based merge logic. Full CRDT/vector clocks are overkill for an append-mostly memory store — start simple.

**Approach:**
- Each memory tracks `modifiedAt` timestamp and `deviceId`
- On sync conflict: union of unique memories (different keys merge automatically), latest-edit-wins for same-key edits
- If same memory edited differently on two devices within 5 minutes: surface conflict to user
- Add `MemorySyncLog` for debugging sync issues
- Upgrade to vector clocks only if real-world conflicts surface frequently

**Implementation note:** `NSUbiquitousKeyValueStore` does not provide conflict notifications natively — it just overwrites. Detect conflicts manually by comparing local vs remote `modifiedAt` timestamps in the `NSUbiquitousKeyValueStoreDidChangeExternallyNotification` handler (listen for `NSUbiquitousKeyValueStoreServerChange` reason code).

- [x] Add `modifiedAt` and `deviceId` to memory model (backward-compatible optional fields)
- [x] Implement timestamp-based merge logic (union + latest-edit-wins for same-ID memories)
- [x] Add conflict detection in `didChangeExternallyNotification` handler (compare local vs remote, merge instead of reload)
- [x] Add `DeviceIdentifier` helper (identifierForVendor on iOS, persisted UUID on macOS)
- [x] Stamp modifiedAt/deviceId on confidence updates and relationship linking
- ~Add conflict resolution UI~ — deferred to v2.1 (auto-resolved with logging sufficient)
- ~Add sync debugging log~ — deferred to v2.1

---

### 14. Adaptive Provider Switching

Suggest the optimal provider (FM vs OpenRouter) based on context — **never auto-switch silently**.

**Critical constraint: Never auto-switch *to* OpenRouter.** OpenRouter uses the user's API key and costs money. Silently sending data to a cloud API when the user chose on-device FM is a trust violation and risks App Store Guideline 5.1.1 (Data Collection). Instead:
- Auto-switching *from* OpenRouter to FM is safe (free, on-device, more private)
- If the user is on FM and a query appears too complex, show a suggestion ("This might work better with Claude — switch?") and let the user confirm

**Signals:**
- Query complexity (ContentTagger estimation)
- Required tools (some only work with FM native calling)
- Response quality history (track regeneration as dissatisfaction signal)
- Network availability

- [x] Add provider fallback banner when FM fails (suggests OpenRouter if API key configured)
- [x] Add "Switch" button in banner with auto-dismiss (8s timeout)
- [x] Guard: only shows when using FM, OpenRouter is configured, and error is not context overflow
- ~Implement complexity scorer~ — dropped (manual switching sufficient)
- ~Track quality signals per provider~ — dropped

---

### 15. Watch App Enhancements

Improve the watchOS companion beyond its current voice-query-and-display model.

**Current state:** Voice input, 4 quick actions, response history (5 items), complications, WatchConnectivity relay to iPhone Agent.

**Improvements:**
- Surface conversation templates (P1 #7) as watch quick actions
- Show Live Activity–style progress on watch during multi-tool execution
- Increase history limit or sync recent sessions from iPhone
- Add complication that shows last response snippet or next-meeting summary

- [x] Wire conversation templates to watch quick actions (Morning Briefing + Meeting Prep replace Timer/Reminders)
- [x] Add `templateId` to `QueryRequest` for Watch→iPhone template passing (backward-compatible optional field)
- [x] Update `WatchQueryHandler` to apply templates before running agent
- ~Add tool execution progress indicator on watch~ — deferred to v2.1
- ~Expand history or sync recent sessions from iPhone~ — deferred to v2.1
- ~Add smart complication with contextual data~ — deferred to v2.1

---

## Cross-Cutting: System Prompt Token Budget

**Problem:** Multiple features inject content into the system prompt — memories, proactive context, plan preview, conversation summary, disabled tools list. The system prompt reserve is only **500 tokens**. Adding all these features simultaneously will blow the budget.

**Solution:** Add a `SystemPromptBudget` tracker that caps total injected context with a strict priority order:

| Priority | Content | Max Tokens | Notes |
|----------|---------|-----------|-------|
| 1 | Core instructions | ~250 | Non-negotiable base prompt |
| 2 | Conversation summary | ~150 | Only if previous messages were trimmed |
| 3 | Memories | ~100 | Top N relevant, truncate if over budget |
| 4 | Proactive context | ~100 | Prefetched calendar/weather/contacts |
| 5 | Disabled tools list | ~50 | Skip entirely if budget exceeded |

Content at each priority level is only included if tokens remain in the 500-token system reserve. Lower-priority content is silently dropped when the budget is tight.

- [x] Implement `SystemPromptBudget` in Agent (tracks running token count, truncates/drops sections when budget exceeded)
- [x] Add per-section token caps to `ClarissaConstants` (core=250, summary=100, memories=80, proactive=80, template=50, disabled=40)
- [x] Update `buildSystemPrompt()` to use budget tracker with 6-level priority system
- [x] Move proactive context injection into `buildSystemPrompt()` (was previously appended outside budget tracking)
- [x] Add unit tests for budget overflow scenarios (8 tests)

---

## App Store Risk Assessment

| # | Feature | App Store Risk | Guideline | Mitigation |
|---|---------|---------------|-----------|------------|
| 1-4 | Foundation + Edit/Regen | None | — | Standard app features |
| 5 | Error Recovery | None | — | Internal error handling |
| 6 | Proactive Intelligence | **Low-Medium** | 5.1.1 (Data Collection) | Toggle defaults OFF, update privacy policy |
| 7 | Templates | **Positive** | 4.2 (Minimum Functionality) | Demonstrates differentiated value |
| 8-12 | Polish features | None | — | Standard app features |
| 13 | iCloud Conflict | None | — | Internal sync logic |
| 14 | Adaptive Switching | **Medium** | 5.1.1 (Data Collection) | Never auto-switch to cloud; require user confirmation |
| 15 | Watch Enhancements | None | — | Standard watchOS patterns |

**General App Store notes:**
- BYOK (Bring Your Own Key) model for OpenRouter is acceptable — Apple does not require IAP for user-provided API keys
- PCC (Private Cloud Compute) integration already has consent toggle — compliant
- All framework permissions (Calendar, Contacts, Location, Reminders) already properly requested with usage descriptions

---

## Priority Matrix

| # | Feature | Effort | Impact | Priority |
|---|---------|--------|--------|----------|
| 1 | Break up ChatViewModel | Medium | High | **P0** |
| 2 | Expand test coverage | Medium | High | **P0** |
| 3 | Smarter token budgeting | Low | High | **P1** |
| 4 | Edit & Regenerate | Low | High | **P1** |
| 5 | Error recovery UX | Low | High | **P1** |
| 6 | Proactive intelligence | Medium | High | **P1** |
| 7 | Conversation templates | Low | Medium | **P1** |
| 8 | Richer tool results | Medium | Medium | **P2** |
| 9 | Conversation branching (full) | High | Medium | **P2** |
| 10 | Memory intelligence | High | Medium | **P2** |
| 11 | Agent plan preview | Medium | Medium | **P2** |
| 12 | Export & sharing | Low | Medium | **P2** |
| 13 | iCloud conflict resolution | Low | Low | **P3** |
| 14 | Adaptive provider switching | Medium | Low | **P3** |
| 15 | Watch app enhancements | Low | Low | **P3** |

---

## Implementation Order

**Phase 1 — Foundation** (P0) ✅
> Break up ChatViewModel + expand test coverage. Everything else gets harder without this.
> **DONE:** ChatViewModel refactored (1164→761 lines), 3 coordinators extracted, 22 new tests added.

**Phase 2 — Core UX** (P1) ✅
> Smarter token budgeting → Error recovery UX → Edit & Regenerate → conversation templates → proactive intelligence.
> **DONE:** Edit & Regenerate (with undo), Error Recovery UX (auto-summarize + retry + manual summarize button), Conversation Templates (4 bundled + custom user templates, picker UI, per-request maxResponseTokens, Siri shortcuts), Smarter Token Budgeting (token-budget-based session trimming + overflow logging), Proactive Intelligence (regex-based weather/calendar detection, parallel prefetch with 2s timeout, Settings toggle, UI indicator on messages), Privacy policy updated.

**Phase 3 — Polish** (P2) ✅
> Richer tool results → export/sharing → agent plan preview → memory intelligence → conversation branching (full).
> **DONE:** Richer Tool Results (expandable weather chart, calendar/contacts deep links, web fetch open, calculator copy), Export & Sharing (PDF export via WKWebView, share as image via ImageRenderer, code block copy with MarkdownContentView), Agent Plan Preview (PlanStep model, ToolPlanView in chat, Live Activity step names), Memory Intelligence (category/temporal/confidence model, decay/boost logic, relationship linking, multi-factor relevance ranker, Review UI with badges).

**Phase 4 — Edge Cases** (P3) ✅
> SystemPromptBudget (cross-cutting) → iCloud conflict resolution → watch template quick actions → provider fallback banner → test coverage.
> **DONE:** SystemPromptBudget tracker (6-priority budget enforcement in buildSystemPrompt, per-section caps in ClarissaConstants), iCloud Conflict Resolution (modifiedAt/deviceId fields, timestamp-based merge, near-simultaneous edit detection, merge-on-change instead of reload), Watch Template Quick Actions (Morning Briefing + Meeting Prep as quick actions, templateId in QueryRequest, WatchQueryHandler applies templates), Adaptive Provider Switching (descoped to fallback banner — suggests OpenRouter when FM fails, auto-dismiss, user-initiated switch), Test Coverage (SystemPromptBudget 8 tests, Memory conflict 5 tests, Context trimming edge cases 10 tests, Watch template queries 5 tests, SharedResult round-trip 5 tests).

---

## v2.0 Release Status: COMPLETE

**Only remaining pre-release action:** Device smoke test for ChatViewModel refactor (send message, switch provider, voice, switch session, try template).

**Intentionally deferred to v2.1:**

- Token budgeting calibration (FM metadata, calibration loop, real token UI)
- ContentTagger Phase 2 (intent classification integration)
- Full conversation branching (#9)
- iCloud conflict resolution UI + sync debug log
- Watch: tool progress indicator, history expansion, smart complication
