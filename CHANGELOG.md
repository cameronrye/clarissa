# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-12-07

### Added

- Initial release of Clarissa
- Interactive terminal UI with Ink
- One-shot command mode with piped input support
- ReAct agent loop for multi-step reasoning
- Built-in tools:
  - `calculator` - Safe mathematical expression evaluation
  - `bash` - Shell command execution with timeout
  - `read_file` - Read file contents
  - `write_file` - Write/create files
  - `patch_file` - Apply patches to files
  - `list_directory` - List directory contents
  - `search_files` - Search for patterns in files
  - `git_status`, `git_diff`, `git_log`, `git_add`, `git_commit`, `git_branch` - Git operations
  - `web_fetch` - Fetch content from URLs
- MCP (Model Context Protocol) server integration
- Session management with save/load/resume
- Memory persistence across sessions
- Context window management with automatic truncation
- Token usage and cost tracking
- Tool confirmation system for dangerous operations
- Multiple model support via OpenRouter
- Prompt enhancement with Ctrl+P
- Markdown rendering in terminal

### Security

- Path traversal protection for file operations
- Session ID validation
- Tool confirmation for destructive operations

