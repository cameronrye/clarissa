# Contributing to Clarissa

Thank you for your interest in contributing to Clarissa! This document provides guidelines and instructions for contributing.

## Getting Started

### Prerequisites

- [Bun](https://bun.sh) v1.0 or later
- An OpenRouter API key (get one at [openrouter.ai](https://openrouter.ai))

### Setup

1. Fork and clone the repository
2. Install dependencies:
   ```bash
   bun install
   ```
3. Copy `.env.example` to `.env` and add your API key:
   ```bash
   cp .env.example .env
   ```

## Development

### Running Locally

```bash
bun run dev
```

### Running Tests

```bash
bun test
```

### Type Checking

```bash
bun run typecheck
```

### Linting

```bash
bun run lint
```

## Code Style

- Use TypeScript for all new code
- Follow existing code patterns and naming conventions
- Keep functions focused and small
- Add JSDoc comments for public APIs
- Use meaningful variable and function names

## Making Changes

1. Create a new branch from `main`:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. Make your changes

3. Add tests for new functionality

4. Ensure all tests pass:
   ```bash
   bun test
   ```

5. Commit your changes with a descriptive message:
   ```bash
   git commit -m "feat: add new feature"
   ```

## Commit Message Format

We follow [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` - New features
- `fix:` - Bug fixes
- `docs:` - Documentation changes
- `test:` - Adding or updating tests
- `refactor:` - Code refactoring
- `chore:` - Maintenance tasks

## Pull Requests

1. Push your branch to your fork
2. Open a pull request against the `main` branch
3. Fill out the PR template with a description of your changes
4. Ensure CI checks pass
5. Wait for review

## Reporting Issues

When reporting issues, please include:

- A clear description of the problem
- Steps to reproduce
- Expected vs actual behavior
- Your environment (OS, Bun version, etc.)

## Adding New Tools

To add a new tool:

1. Create a new file in `src/tools/`
2. Use the `defineTool` helper from `./base.ts`
3. Register the tool in `src/tools/index.ts`
4. Add tests for the tool
5. Update documentation if needed

Example:

```typescript
import { z } from "zod";
import { defineTool } from "./base.ts";

export const myTool = defineTool({
  name: "my_tool",
  description: "What the tool does",
  parameters: z.object({
    input: z.string().describe("Input description"),
  }),
  execute: async ({ input }) => {
    // Implementation
    return { result: "output" };
  },
});
```

## Questions?

Feel free to open an issue for any questions about contributing.

---

Made with love by Cameron Rye - [rye.dev](https://rye.dev)

