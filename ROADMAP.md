# Clarissa Roadmap

> AI-powered terminal assistant with tool execution capabilities

---

## Completed Features (v1.2.0)

### Apple Foundation Model with Tools
- [x] Full tool calling support for Apple Intelligence on-device AI
- [x] All built-in tools work with Apple Foundation Model (file ops, git, bash, web fetch)
- [x] Intelligent tool limit handling (max 10 tools for optimal Apple AI performance)
- [x] Channel token parsing for clean output from thinking models
- [x] Automatic retry without tools when model returns null responses
- [x] Real-time streaming with channel token filtering
- [x] Comprehensive Apple AI test suite (`bun test:apple-ai`)

## Completed Features (v1.1.0)

### Multi-Provider LLM Support
- [x] Provider abstraction layer with unified interface
- [x] OpenRouter provider (cloud) - 100+ models
- [x] OpenAI provider (cloud) - Direct GPT API
- [x] Anthropic provider (cloud) - Direct Claude API
- [x] Apple Intelligence provider (local) - macOS 26+ on-device AI
- [x] LM Studio provider (local) - Desktop app integration
- [x] Local Llama provider (local) - Direct GGUF inference via node-llama-cpp
- [x] Provider switching with `/provider` command
- [x] Automatic provider detection and priority selection
- [x] Preferences persistence for last used provider/model

### Local Model Support
- [x] GGUF model download from Hugging Face (`clarissa download`)
- [x] Curated recommended models list (Qwen 3, Gemma 3, Llama 4, DeepSeek R1, etc.)
- [x] Download progress tracking
- [x] Model listing (`clarissa models`)
- [x] GPU layer configuration for local inference
- [x] Flash attention support

### Auto-Update System
- [x] Version checking against npm registry
- [x] `clarissa upgrade` command
- [x] Package manager detection (bun, pnpm, npm)
- [x] Background update notifications

### API Improvements
- [x] Retry logic with exponential backoff and jitter
- [x] Rate limit handling for all providers
- [x] Streaming support for all providers

## Completed Features (v1.0.0)

### Core Operations
- [x] `read_file` - View files with line numbers and range support
- [x] `write_file` - Create or overwrite files
- [x] `patch_file` - String replacement editing (str-replace style)
- [x] `list_directory` - Tree view with filtering
- [x] `search_files` - Regex search across files (grep-like)

### Git Integration
- [x] `git_status` - Show repository status
- [x] `git_diff` - Show changes (staged/unstaged)
- [x] `git_log` - View commit history
- [x] `git_add` - Stage files
- [x] `git_commit` - Commit with AI-generated messages
- [x] `git_branch` - List/create/switch branches

### System & Web
- [x] `bash` - Execute shell commands with timeout
- [x] `calculator` - Safe mathematical expression evaluation
- [x] `web_fetch` - Fetch and parse web pages

### Session Management
- [x] Save/load/delete conversations
- [x] Session listing with `/sessions`
- [x] Memory persistence across sessions (`/remember`, `/memories`, `/forget`)

### User Experience
- [x] Tool confirmation UI with `/yolo` toggle
- [x] Interactive and one-shot command modes
- [x] Piped input support
- [x] Prompt enhancement with Ctrl+P
- [x] Markdown rendering with syntax highlighting
- [x] Input history navigation

### Context Management
- [x] Token counting per message
- [x] Running cost estimate display
- [x] Auto-truncation when approaching limit
- [x] Context window display with `/context`

### MCP Support
- [x] MCP client implementation
- [x] Connect to stdio MCP servers
- [x] Dynamic tool registration from MCP

### Multi-Model
- [x] Model switching mid-conversation (`/model`)
- [x] CLI model selection (`-m, --model`)
- [x] Model listing (`--list-models`)

---

## Future Roadmap

### Near Term
- [ ] HTTP/SSE MCP server transport
- [ ] File context references
- [x] Image/vision analysis
- [ ] Model delete command for local models

### Medium Term
- [ ] Codebase indexing with embeddings
- [ ] Semantic search across codebase
- [ ] Model comparison mode
- [ ] Fallback model configuration
- [ ] Provider-specific model recommendations

### Long Term
- [ ] Integrated linting with auto-fix
- [ ] Test runner integration
- [ ] Project scaffolding templates
- [ ] Multi-agent collaboration

---

## Architecture

### Tool Categories
- `file` - File system operations
- `git` - Version control
- `system` - Shell/bash execution
- `web` - Web fetching
- `mcp` - External MCP server tools

### Tool Properties
```typescript
interface Tool {
  name: string;
  description: string;
  category: 'file' | 'git' | 'system' | 'web' | 'mcp';
  requiresConfirmation: boolean;
  parameters: ZodSchema;
  execute: (input) => Promise<output>;
}
```

---

Made with ❤️ by [Cameron Rye](https://rye.dev)

