import type { Message } from "./types.ts";
import { usageTracker } from "./usage.ts";

// Default context window sizes for common models
const MODEL_CONTEXT_SIZES: Record<string, number> = {
  // Anthropic models
  "anthropic/claude-sonnet-4": 200000,
  "anthropic/claude-opus-4": 200000,
  "anthropic/claude-3.5-sonnet": 200000,
  // OpenAI models
  "openai/gpt-4o": 128000,
  "openai/gpt-4o-mini": 128000,
  // Google models
  "google/gemini-2.0-flash": 1000000,
  "google/gemini-2.5-pro-preview": 1000000,
  // Meta models
  "meta-llama/llama-3.3-70b-instruct": 128000,
  // DeepSeek models
  "deepseek/deepseek-chat-v3-0324": 128000,
  // Default fallback
  default: 128000,
};

// Reserve tokens for response
const RESPONSE_RESERVE = 4096;

export interface ContextStats {
  totalTokens: number;
  maxTokens: number;
  usagePercent: number;
  messageCount: number;
}

export interface DetailedContextStats extends ContextStats {
  model: string;
  responseReserve: number;
  breakdown: {
    system: { tokens: number; count: number };
    user: { tokens: number; count: number };
    assistant: { tokens: number; count: number };
    tool: { tokens: number; count: number };
  };
}

/**
 * Context window manager - tracks and manages conversation context
 */
class ContextManager {
  private maxTokens: number = MODEL_CONTEXT_SIZES.default ?? 128000;
  private currentModel: string = "default";

  /**
   * Set the current model to determine context window size
   */
  setModel(model: string): void {
    this.currentModel = model;
    this.maxTokens = MODEL_CONTEXT_SIZES[model] ?? MODEL_CONTEXT_SIZES.default ?? 128000;
  }

  /**
   * Get the maximum context window size
   */
  getMaxTokens(): number {
    return this.maxTokens;
  }

  /**
   * Estimate tokens for a message
   */
  estimateMessageTokens(message: Message): number {
    let tokens = 0;

    // Content tokens
    if (message.content) {
      tokens += usageTracker.estimateTokens(message.content);
    }

    // Tool call tokens
    if (message.tool_calls) {
      for (const tc of message.tool_calls) {
        tokens += usageTracker.estimateTokens(tc.function.name);
        tokens += usageTracker.estimateTokens(tc.function.arguments);
      }
    }

    // Role overhead (~4 tokens per message)
    tokens += 4;

    return tokens;
  }

  /**
   * Estimate total tokens for a conversation
   */
  estimateConversationTokens(messages: Message[]): number {
    return messages.reduce((sum, msg) => sum + this.estimateMessageTokens(msg), 0);
  }

  /**
   * Get context statistics
   */
  getStats(messages: Message[]): ContextStats {
    const totalTokens = this.estimateConversationTokens(messages);
    const availableTokens = this.maxTokens - RESPONSE_RESERVE;

    return {
      totalTokens,
      maxTokens: availableTokens,
      usagePercent: Math.round((totalTokens / availableTokens) * 100),
      messageCount: messages.length,
    };
  }

  /**
   * Check if context is approaching limit
   */
  isNearLimit(messages: Message[], threshold: number = 0.8): boolean {
    const stats = this.getStats(messages);
    return stats.usagePercent >= threshold * 100;
  }

  /**
   * Truncate messages to fit within context window
   * Keeps system prompt and recent messages
   * Ensures tool_calls and their results are kept together
   */
  truncateToFit(messages: Message[]): Message[] {
    const availableTokens = this.maxTokens - RESPONSE_RESERVE;
    let totalTokens = this.estimateConversationTokens(messages);

    if (totalTokens <= availableTokens) {
      return messages;
    }

    // Keep system prompt (first message) and remove oldest non-system messages
    const result: Message[] = [];
    const systemMessages = messages.filter((m) => m.role === "system");
    const nonSystemMessages = messages.filter((m) => m.role !== "system");

    // Always keep system messages
    result.push(...systemMessages);
    totalTokens = this.estimateConversationTokens(systemMessages);

    // Group messages into atomic units (user, assistant+tool_results, etc.)
    // Tool results must stay with their corresponding assistant message
    const messageGroups: Message[][] = [];
    let currentGroup: Message[] = [];

    for (const msg of nonSystemMessages) {
      if (msg.role === "user") {
        // User messages start a new group
        if (currentGroup.length > 0) {
          messageGroups.push(currentGroup);
        }
        currentGroup = [msg];
      } else if (msg.role === "assistant") {
        // Assistant messages start a new group (but include in current if empty)
        if (currentGroup.length > 0 && currentGroup[0]?.role !== "user") {
          messageGroups.push(currentGroup);
          currentGroup = [msg];
        } else {
          currentGroup.push(msg);
        }
      } else if (msg.role === "tool") {
        // Tool results must stay with their assistant message
        currentGroup.push(msg);
      }
    }
    if (currentGroup.length > 0) {
      messageGroups.push(currentGroup);
    }

    // Add groups from newest to oldest until we hit the limit
    const reversedGroups = [...messageGroups].reverse();
    const toAdd: Message[] = [];

    for (const group of reversedGroups) {
      const groupTokens = group.reduce((sum, msg) => sum + this.estimateMessageTokens(msg), 0);
      if (totalTokens + groupTokens <= availableTokens) {
        toAdd.unshift(...group);
        totalTokens += groupTokens;
      } else {
        break;
      }
    }

    result.push(...toAdd);
    return result;
  }

  /**
   * Format context stats for display
   */
  formatStats(messages: Message[]): string {
    const stats = this.getStats(messages);
    return `${stats.totalTokens.toLocaleString()}/${stats.maxTokens.toLocaleString()} tokens (${stats.usagePercent}%)`;
  }

  /**
   * Get detailed context statistics with breakdown by message type
   */
  getDetailedStats(messages: Message[]): DetailedContextStats {
    const stats = this.getStats(messages);

    const breakdown = {
      system: { tokens: 0, count: 0 },
      user: { tokens: 0, count: 0 },
      assistant: { tokens: 0, count: 0 },
      tool: { tokens: 0, count: 0 },
    };

    for (const msg of messages) {
      const tokens = this.estimateMessageTokens(msg);
      const role = msg.role as keyof typeof breakdown;
      if (breakdown[role]) {
        breakdown[role].tokens += tokens;
        breakdown[role].count += 1;
      }
    }

    return {
      ...stats,
      model: this.currentModel,
      responseReserve: RESPONSE_RESERVE,
      breakdown,
    };
  }
}

export const contextManager = new ContextManager();

