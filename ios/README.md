# Clarissa iOS

Native iOS version of Clarissa, built with Swift and SwiftUI.

## Requirements

- Xcode 26 beta or later
- iOS 26+ device or simulator
- macOS 26+ for Mac Catalyst support

## Features

- On-device AI using Apple Foundation Models
- Cloud fallback via OpenRouter API
- Calendar integration (create, list, search events)
- Contacts integration (search, view contacts)
- Web content fetching
- Calculator
- Session persistence
- Long-term memory

## Project Structure

```
ios/Clarissa/
├── Sources/
│   ├── App/           # App entry point and state
│   ├── Agent/         # ReAct agent implementation
│   ├── LLM/           # LLM providers (Foundation Models, OpenRouter)
│   ├── Tools/         # Tool implementations
│   ├── UI/            # SwiftUI views
│   └── Persistence/   # Session and memory management
├── Resources/         # Info.plist, assets
└── Tests/             # Unit tests
```

## Setup

### Option 1: Swift Package (Recommended for development)

1. Open the package in Xcode:
   ```bash
   cd ios/Clarissa
   open Package.swift
   ```

2. Select an iOS 26+ simulator or device

3. Build and run (Cmd+R)

### Option 2: Create Xcode Project

1. Open Xcode and create a new iOS App project

2. Add the package as a local dependency:
   - File > Add Package Dependencies
   - Click "Add Local..."
   - Select the `ios/Clarissa` directory

3. Import and use `Clarissa` in your app

## Configuration

### OpenRouter API (Optional)

For cloud LLM fallback when on-device AI is unavailable:

1. Get an API key from [OpenRouter](https://openrouter.ai/keys)
2. Open Settings in the app
3. Enter your API key

### Permissions

The app requires the following permissions:
- **Calendar**: To create and manage events
- **Contacts**: To search and view contacts

## Shared Configuration

Tool schemas and prompts are shared with the CLI version in `/shared`:

- `/shared/prompts/system.json` - System prompt configuration
- `/shared/tools/*.json` - Tool definitions

## Architecture

### Agent Layer

The agent implements a ReAct (Reasoning + Acting) loop:

1. Receive user message
2. Send to LLM with available tools
3. If LLM requests tool calls, execute them
4. Return tool results to LLM
5. Repeat until LLM provides final response

### LLM Providers

- **FoundationModelsProvider**: Uses Apple's on-device Foundation Models (iOS 26+)
- **OpenRouterProvider**: Cloud fallback using OpenRouter API

### Tools

Tools are registered with the `ToolRegistry` and implement the `ClarissaTool` protocol:

- `CalendarTool`: EventKit integration
- `ContactsTool`: Contacts framework integration
- `WebFetchTool`: URLSession-based web fetching
- `CalculatorTool`: Mathematical expression evaluation

---

Made with love by Cameron Rye - [rye.dev](https://rye.dev)

