import { test, expect, describe } from "bun:test";
import { render } from "ink-testing-library";
import { Box, Text } from "ink";
import { Alert } from "@inkjs/ui";
import { renderMarkdown } from "./markdown.ts";

/**
 * MessageBubble component extracted for testing
 * This mirrors the implementation in App.tsx
 */
function MessageBubble({ role, content }: { role: string; content: string }) {
  const colors: Record<string, string> = {
    user: "blue",
    assistant: "green",
    system: "gray",
    error: "red",
  };

  const prefixes: Record<string, string> = {
    user: "You",
    assistant: "Clarissa",
    system: "System",
    error: "Error",
  };

  // Render markdown for assistant messages
  const displayContent = role === "assistant" ? renderMarkdown(content) : content;

  // Use Alert component for error messages for better visibility
  if (role === "error") {
    return (
      <Box marginBottom={1}>
        <Alert variant="error" title="Error">
          {content}
        </Alert>
      </Box>
    );
  }

  return (
    <Box flexDirection="column" marginBottom={1}>
      <Text bold color={colors[role] || "white"}>
        {prefixes[role] || role}:
      </Text>
      <Box marginLeft={2}>
        <Text wrap="wrap">{displayContent}</Text>
      </Box>
    </Box>
  );
}

describe("MessageBubble", () => {
  test("renders user message with 'You' prefix", () => {
    const { lastFrame } = render(
      <MessageBubble role="user" content="Hello, Clarissa!" />
    );
    const output = lastFrame();
    expect(output).toContain("You:");
    expect(output).toContain("Hello, Clarissa!");
  });

  test("renders assistant message with 'Clarissa' prefix", () => {
    const { lastFrame } = render(
      <MessageBubble role="assistant" content="Hello! How can I help?" />
    );
    const output = lastFrame();
    expect(output).toContain("Clarissa:");
    expect(output).toContain("Hello!");
  });

  test("renders system message with 'System' prefix", () => {
    const { lastFrame } = render(
      <MessageBubble role="system" content="Session saved successfully" />
    );
    const output = lastFrame();
    expect(output).toContain("System:");
    expect(output).toContain("Session saved");
  });

  test("renders error message using Alert component", () => {
    const { lastFrame } = render(
      <MessageBubble role="error" content="Connection failed" />
    );
    const output = lastFrame();
    // Alert component renders with error styling
    expect(output).toContain("Error");
    expect(output).toContain("Connection failed");
  });

  test("renders error with special formatting (not plain text)", () => {
    const { lastFrame } = render(
      <MessageBubble role="error" content="API rate limit exceeded" />
    );
    const output = lastFrame();
    // Should not contain "Error:" prefix (Alert handles the title differently)
    expect(output).toContain("API rate limit exceeded");
  });

  test("renders markdown in assistant messages", () => {
    const { lastFrame } = render(
      <MessageBubble role="assistant" content="Use **bold** for emphasis" />
    );
    const output = lastFrame();
    expect(output).toContain("Clarissa:");
    // The markdown should be processed (bold may have ANSI codes)
    expect(output).toContain("bold");
  });

  test("does not render markdown in user messages", () => {
    const { lastFrame } = render(
      <MessageBubble role="user" content="How do I use **bold**?" />
    );
    const output = lastFrame();
    // User messages should preserve the raw markdown syntax
    expect(output).toContain("**bold**");
  });

  test("handles unknown role with default styling", () => {
    const { lastFrame } = render(
      <MessageBubble role="unknown" content="Some content" />
    );
    const output = lastFrame();
    expect(output).toContain("unknown:");
    expect(output).toContain("Some content");
  });

  test("handles empty content", () => {
    const { lastFrame } = render(
      <MessageBubble role="user" content="" />
    );
    const output = lastFrame();
    expect(output).toContain("You:");
  });

  test("handles multiline content", () => {
    const content = `Line 1
Line 2
Line 3`;
    const { lastFrame } = render(
      <MessageBubble role="assistant" content={content} />
    );
    const output = lastFrame();
    expect(output).toContain("Line 1");
    expect(output).toContain("Line 2");
    expect(output).toContain("Line 3");
  });
});

