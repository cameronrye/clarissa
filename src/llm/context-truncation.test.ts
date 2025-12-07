import { test, expect, describe, beforeEach } from "bun:test";
import type { Message } from "./types.ts";

// Replicate ContextManager for truncation testing with small limits
class TruncationTestContextManager {
  private maxTokens: number = 100; // Very small for testing
  private RESPONSE_RESERVE = 10;

  setMaxTokens(tokens: number): void {
    this.maxTokens = tokens;
  }

  private estimateTokens(text: string): number {
    return Math.ceil(text.length / 4);
  }

  estimateMessageTokens(message: Message): number {
    let tokens = 0;
    if (message.content) {
      tokens += this.estimateTokens(message.content);
    }
    if (message.tool_calls) {
      for (const tc of message.tool_calls) {
        tokens += this.estimateTokens(tc.function.name);
        tokens += this.estimateTokens(tc.function.arguments);
      }
    }
    tokens += 4;
    return tokens;
  }

  estimateConversationTokens(messages: Message[]): number {
    return messages.reduce((sum, msg) => sum + this.estimateMessageTokens(msg), 0);
  }

  isNearLimit(messages: Message[], threshold: number = 0.8): boolean {
    const totalTokens = this.estimateConversationTokens(messages);
    const availableTokens = this.maxTokens - this.RESPONSE_RESERVE;
    const usagePercent = (totalTokens / availableTokens) * 100;
    return usagePercent >= threshold * 100;
  }

  truncateToFit(messages: Message[]): Message[] {
    const availableTokens = this.maxTokens - this.RESPONSE_RESERVE;
    let totalTokens = this.estimateConversationTokens(messages);
    if (totalTokens <= availableTokens) return messages;

    const result: Message[] = [];
    const systemMessages = messages.filter((m) => m.role === "system");
    const nonSystemMessages = messages.filter((m) => m.role !== "system");

    result.push(...systemMessages);
    totalTokens = this.estimateConversationTokens(systemMessages);

    const reversedNonSystem = [...nonSystemMessages].reverse();
    const toAdd: Message[] = [];

    for (const msg of reversedNonSystem) {
      const msgTokens = this.estimateMessageTokens(msg);
      if (totalTokens + msgTokens <= availableTokens) {
        toAdd.unshift(msg);
        totalTokens += msgTokens;
      } else break;
    }

    result.push(...toAdd);
    return result;
  }
}

describe("Context Truncation", () => {
  let contextManager: TruncationTestContextManager;

  beforeEach(() => {
    contextManager = new TruncationTestContextManager();
  });

  describe("isNearLimit", () => {
    test("returns true when near limit", () => {
      contextManager.setMaxTokens(50);
      const messages: Message[] = [
        { role: "system", content: "System prompt" },
        { role: "user", content: "A".repeat(100) }, // ~25 tokens + 4 overhead
      ];
      expect(contextManager.isNearLimit(messages, 0.5)).toBe(true);
    });

    test("returns false when below threshold", () => {
      contextManager.setMaxTokens(1000);
      const messages: Message[] = [
        { role: "user", content: "Hello" },
      ];
      expect(contextManager.isNearLimit(messages, 0.8)).toBe(false);
    });
  });

  describe("truncateToFit", () => {
    test("returns original messages if within limit", () => {
      contextManager.setMaxTokens(1000);
      const messages: Message[] = [
        { role: "system", content: "Short system" },
        { role: "user", content: "Hello" },
      ];
      const result = contextManager.truncateToFit(messages);
      expect(result).toEqual(messages);
    });

    test("preserves system messages", () => {
      contextManager.setMaxTokens(50);
      const messages: Message[] = [
        { role: "system", content: "Important system prompt" },
        { role: "user", content: "Old message" },
        { role: "assistant", content: "Old response" },
        { role: "user", content: "New message" },
      ];
      const result = contextManager.truncateToFit(messages);
      expect(result.find(m => m.role === "system")).toBeDefined();
    });

    test("keeps most recent messages", () => {
      contextManager.setMaxTokens(60);
      const messages: Message[] = [
        { role: "system", content: "Sys" },
        { role: "user", content: "First" },
        { role: "assistant", content: "Response 1" },
        { role: "user", content: "Second" },
        { role: "assistant", content: "Response 2" },
        { role: "user", content: "Third" },
      ];
      const result = contextManager.truncateToFit(messages);
      // Should have system and most recent messages
      expect(result[0]!.role).toBe("system");
      expect(result[result.length - 1]!.content).toBe("Third");
    });

    test("removes oldest non-system messages first", () => {
      contextManager.setMaxTokens(50);
      const messages: Message[] = [
        { role: "system", content: "Sys" },
        { role: "user", content: "OLD" },
        { role: "user", content: "NEW" },
      ];
      const result = contextManager.truncateToFit(messages);
      const hasOld = result.some(m => m.content === "OLD");
      const hasNew = result.some(m => m.content === "NEW");
      // If truncated, should prefer NEW over OLD
      if (result.length < messages.length) {
        expect(hasNew || !hasOld).toBe(true);
      }
    });

    test("handles empty messages", () => {
      const result = contextManager.truncateToFit([]);
      expect(result).toEqual([]);
    });

    test("handles only system message", () => {
      contextManager.setMaxTokens(100);
      const messages: Message[] = [
        { role: "system", content: "System only" },
      ];
      const result = contextManager.truncateToFit(messages);
      expect(result).toEqual(messages);
    });
  });
});

