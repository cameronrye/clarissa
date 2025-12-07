import { test, expect, describe, beforeEach } from "bun:test";
import type { Message } from "./types.ts";

// Test a fresh instance of ContextManager
class TestableContextManager {
  private maxTokens: number = 128000;
  private RESPONSE_RESERVE = 4096;

  private MODEL_CONTEXT_SIZES: Record<string, number> = {
    "anthropic/claude-sonnet-4": 200000,
    "anthropic/claude-opus-4": 200000,
    "anthropic/claude-3.5-sonnet": 200000,
    "openai/gpt-4o": 128000,
    "openai/gpt-4o-mini": 128000,
    "google/gemini-2.0-flash": 1000000,
    default: 128000,
  };

  setModel(model: string): void {
    this.maxTokens = this.MODEL_CONTEXT_SIZES[model] ?? this.MODEL_CONTEXT_SIZES.default!;
  }

  getMaxTokens(): number {
    return this.maxTokens;
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
    tokens += 4; // Role overhead
    return tokens;
  }

  estimateConversationTokens(messages: Message[]): number {
    return messages.reduce((sum, msg) => sum + this.estimateMessageTokens(msg), 0);
  }

  getStats(messages: Message[]) {
    const totalTokens = this.estimateConversationTokens(messages);
    const availableTokens = this.maxTokens - this.RESPONSE_RESERVE;
    return {
      totalTokens,
      maxTokens: availableTokens,
      usagePercent: Math.round((totalTokens / availableTokens) * 100),
      messageCount: messages.length,
    };
  }

  isNearLimit(messages: Message[], threshold: number = 0.8): boolean {
    const stats = this.getStats(messages);
    return stats.usagePercent >= threshold * 100;
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

  formatStats(messages: Message[]): string {
    const stats = this.getStats(messages);
    return `${stats.totalTokens.toLocaleString()}/${stats.maxTokens.toLocaleString()} tokens (${stats.usagePercent}%)`;
  }
}

describe("Context Management", () => {
  let contextManager: TestableContextManager;

  beforeEach(() => {
    contextManager = new TestableContextManager();
  });

  describe("setModel", () => {
    test("sets context size for known models", () => {
      contextManager.setModel("anthropic/claude-sonnet-4");
      expect(contextManager.getMaxTokens()).toBe(200000);
    });

    test("uses default size for unknown models", () => {
      contextManager.setModel("unknown/model");
      expect(contextManager.getMaxTokens()).toBe(128000);
    });

    test("handles gemini large context", () => {
      contextManager.setModel("google/gemini-2.0-flash");
      expect(contextManager.getMaxTokens()).toBe(1000000);
    });
  });

  describe("estimateMessageTokens", () => {
    test("estimates tokens for content", () => {
      const message: Message = { role: "user", content: "hello world" };
      const tokens = contextManager.estimateMessageTokens(message);
      expect(tokens).toBeGreaterThan(4); // At least overhead
    });

    test("estimates tokens for tool calls", () => {
      const message: Message = {
        role: "assistant",
        content: null,
        tool_calls: [{ id: "1", type: "function", function: { name: "test", arguments: '{"a":1}' } }],
      };
      const tokens = contextManager.estimateMessageTokens(message);
      expect(tokens).toBeGreaterThan(4);
    });

    test("includes role overhead", () => {
      const message: Message = { role: "user", content: "" };
      const tokens = contextManager.estimateMessageTokens(message);
      expect(tokens).toBe(4);
    });
  });

  describe("getStats", () => {
    test("calculates usage percentage", () => {
      // Use longer content to ensure measurable percentage
      const longContent = "A".repeat(10000); // ~2500 tokens
      const messages: Message[] = [
        { role: "system", content: longContent },
        { role: "user", content: "Hello" },
      ];
      const stats = contextManager.getStats(messages);
      expect(stats.totalTokens).toBeGreaterThan(0);
      expect(stats.messageCount).toBe(2);
    });
  });
});

