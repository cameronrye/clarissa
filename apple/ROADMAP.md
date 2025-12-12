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

- [x] Siri Shortcuts (Ask Clarissa, New Conversation)
- [x] macOS menu bar commands
- [x] macOS keyboard shortcuts
- [x] Keychain API key storage

---

## Future Roadmap

### Near Term

- [ ] watchOS companion app
- [ ] Widget for quick questions
- [ ] Share extension for web pages
- [ ] iCloud sync for sessions and memories
- [ ] Multi-language voice support

### Medium Term

- [ ] Image analysis via Vision framework
- [ ] Document scanning and OCR
- [ ] Apple Music integration
- [ ] HomeKit device control
- [ ] Focus mode awareness
- [ ] Live Activities for long-running tasks

### Long Term

- [ ] visionOS spatial interface
- [ ] CarPlay dashboard
- [ ] Apple Watch complications
- [ ] Multi-agent conversations
- [ ] Custom trained adapters

---

## Architecture Goals

### Performance

- Minimize memory footprint on device
- Optimize Foundation Models session reuse
- Efficient context window management
- Background task completion

### Privacy

- All processing on-device by default
- No telemetry or analytics
- Keychain-secured credentials
- Transparent permission requests

### Accessibility

- VoiceOver full support
- Dynamic Type scaling
- Reduce Motion compatibility
- Reduce Transparency fallbacks
- High Contrast mode support

---

## Platform Support Matrix

| Platform | Status | Minimum Version |
|----------|--------|-----------------|
| iOS | ✅ Available | iOS 26.0 |
| macOS | ✅ Available | macOS 26.0 |
| iPadOS | ✅ Available | iPadOS 26.0 |
| watchOS | 🔜 Planned | watchOS 26.0 |
| visionOS | 🔮 Future | visionOS 26.0 |

---

Made with ❤️ by [Cameron Rye](https://rye.dev)
