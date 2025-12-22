/**
 * OpenRouter LLM Provider
 *
 * Cloud-based provider using OpenRouter API for access to various LLM models.
 */

import { OpenRouter } from "@openrouter/sdk";
import type { Message } from "../types.ts";
import type {
  LLMProvider,
  ProviderInfo,
  ProviderStatus,
  ChatOptions,
  ChatResponse,
} from "./types.ts";
import { usageTracker } from "../usage.ts";

// Retry configuration
const RETRY_CONFIG = {
  maxRetries: 3,
  baseDelayMs: 1000,
  maxDelayMs: 10000,
  retryableStatusCodes: [429, 500, 502, 503, 504],
};

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function getRetryDelay(attempt: number): number {
  const exponentialDelay = RETRY_CONFIG.baseDelayMs * Math.pow(2, attempt);
  const jitter = Math.random() * 0.3 * exponentialDelay;
  return Math.min(exponentialDelay + jitter, RETRY_CONFIG.maxDelayMs);
}

function isRetryableError(error: unknown): boolean {
  if (error instanceof Error) {
    const message = error.message.toLowerCase();
    if (message.includes("rate limit") || message.includes("too many requests")) return true;
    if (message.includes("timeout") || message.includes("timed out")) return true;
    if (message.includes("network") || message.includes("connection")) return true;
    for (const code of RETRY_CONFIG.retryableStatusCodes) {
      if (message.includes(String(code))) return true;
    }
  }
  return false;
}

/**
 * Convert error to user-friendly message (iOS pattern)
 */
function getUserFriendlyError(error: unknown): Error {
  if (!(error instanceof Error)) {
    return new Error(String(error));
  }

  const message = error.message;

  // Check for HTTP status codes in error message
  if (message.includes("401") || message.toLowerCase().includes("unauthorized")) {
    return new Error("Invalid API key. Please check your OpenRouter API key.");
  }
  if (message.includes("402") || message.toLowerCase().includes("payment required")) {
    return new Error("Insufficient credits. Please add credits to your OpenRouter account.");
  }
  if (message.includes("429") || message.toLowerCase().includes("rate limit")) {
    return new Error("Rate limit exceeded. Please wait a moment and try again.");
  }
  if (message.includes("500") || message.includes("502") || message.includes("503") || message.includes("504")) {
    return new Error("OpenRouter server error. Please try again later.");
  }
  if (message.toLowerCase().includes("network") || message.toLowerCase().includes("connection")) {
    return new Error("Network error. Please check your internet connection.");
  }

  return error;
}

/**
 * Type for streaming chunk from OpenRouter SDK.
 * The SDK's AsyncIterable yields chunks with this structure.
 * We define this explicitly rather than relying on SDK types to handle
 * potential version mismatches gracefully.
 */
interface SDKStreamChunk {
  id?: string;
  choices?: Array<{
    delta?: {
      role?: string;
      content?: string | null;
      toolCalls?: Array<{
        index?: number;
        id?: string;
        function?: { name?: string; arguments?: string };
      }>;
    };
    finishReason?: string | null;
    index?: number;
  }>;
}

/**
 * Type guard to safely extract stream chunk data.
 * Returns the chunk if it matches expected structure, undefined otherwise.
 */
function parseStreamChunk(rawChunk: unknown): SDKStreamChunk | undefined {
  if (typeof rawChunk !== "object" || rawChunk === null) {
    return undefined;
  }
  // The SDK returns objects with choices array - validate basic structure
  const chunk = rawChunk as Record<string, unknown>;
  if (!Array.isArray(chunk.choices)) {
    return undefined;
  }
  return rawChunk as SDKStreamChunk;
}

function transformMessagesForSDK(
  messages: Message[]
): Parameters<OpenRouter["chat"]["send"]>[0]["messages"] {
  return messages.map((msg) => {
    if (msg.role === "tool") {
      return { role: "tool" as const, content: msg.content || "", toolCallId: msg.tool_call_id || "" };
    }
    if (msg.role === "assistant" && msg.tool_calls) {
      return {
        role: "assistant" as const,
        content: msg.content,
        toolCalls: msg.tool_calls.map((tc) => ({ id: tc.id, type: "function" as const, function: tc.function })),
      };
    }
    return { role: msg.role, content: msg.content || "" };
  }) as Parameters<OpenRouter["chat"]["send"]>[0]["messages"];
}

// Default models available on OpenRouter
const DEFAULT_OPENROUTER_MODELS = [
  "anthropic/claude-sonnet-4",
  "anthropic/claude-opus-4",
  "anthropic/claude-3.5-sonnet",
  "openai/gpt-4o",
  "openai/gpt-4o-mini",
  "google/gemini-2.0-flash",
  "google/gemini-2.5-pro-preview",
  "meta-llama/llama-3.3-70b-instruct",
  "deepseek/deepseek-chat-v3-0324",
] as const;

export class OpenRouterProvider implements LLMProvider {
  private client: OpenRouter | null = null;
  private apiKey: string;
  private defaultModel: string;

  readonly info: ProviderInfo;

  constructor(
    apiKey: string,
    defaultModel: string = "anthropic/claude-sonnet-4",
    customModels?: readonly string[]
  ) {
    this.apiKey = apiKey;
    this.defaultModel = defaultModel;
    this.info = {
      id: "openrouter",
      name: "OpenRouter",
      description: "Cloud-based access to various LLM models via OpenRouter API",
      capabilities: {
        streaming: true,
        toolCalling: true,
        structuredOutput: true,
        embeddings: false,
        local: false,
      },
      availableModels: customModels ?? DEFAULT_OPENROUTER_MODELS,
    };
  }

  async checkAvailability(): Promise<ProviderStatus> {
    if (!this.apiKey) {
      return { available: false, reason: "No API key configured" };
    }
    return { available: true, model: this.defaultModel };
  }

  async initialize(): Promise<void> {
    this.client = new OpenRouter({ apiKey: this.apiKey });
  }

  async chat(messages: Message[], options?: ChatOptions): Promise<ChatResponse> {
    if (!this.client) await this.initialize();
    const client = this.client!;
    const model = options?.model || this.defaultModel;
    const tools = options?.tools as Parameters<typeof client.chat.send>[0]["tools"];
    let lastError: Error | undefined;

    for (let attempt = 0; attempt <= RETRY_CONFIG.maxRetries; attempt++) {
      try {
        return await this.doStreamingChat(client, messages, model, tools, options?.onChunk);
      } catch (error) {
        lastError = error instanceof Error ? error : new Error(String(error));
        if (attempt < RETRY_CONFIG.maxRetries && isRetryableError(error)) {
          await sleep(getRetryDelay(attempt));
          continue;
        }
        // Convert to user-friendly error message (iOS pattern)
        throw getUserFriendlyError(lastError);
      }
    }
    throw getUserFriendlyError(lastError ?? new Error("Unexpected retry loop exit"));
  }

  private async doStreamingChat(
    client: OpenRouter,
    messages: Message[],
    model: string,
    tools: Parameters<typeof client.chat.send>[0]["tools"],
    onChunk?: (content: string) => void
  ): Promise<ChatResponse> {
    const stream = await client.chat.send({
      model,
      messages: transformMessagesForSDK(messages),
      tools,
      stream: true,
    });

    let content = "";
    const toolCallsMap = new Map<number, { id: string; type: "function"; function: { name: string; arguments: string } }>();

    for await (const rawChunk of stream) {
      const chunk = parseStreamChunk(rawChunk);
      if (!chunk) continue;

      const delta = chunk.choices?.[0]?.delta;
      if (!delta) continue;

      if (delta.content) {
        content += delta.content;
        onChunk?.(delta.content);
      }

      if (delta.toolCalls) {
        for (const tc of delta.toolCalls) {
          const index = tc.index ?? 0;
          if (tc.id) {
            toolCallsMap.set(index, {
              id: tc.id,
              type: "function",
              function: { name: tc.function?.name || "", arguments: tc.function?.arguments || "" },
            });
          } else if (tc.function) {
            const existing = toolCallsMap.get(index);
            if (existing) {
              if (tc.function.name) existing.function.name += tc.function.name;
              if (tc.function.arguments) existing.function.arguments += tc.function.arguments;
            }
          }
        }
      }
    }

    const toolCalls = Array.from(toolCallsMap.values());
    const promptText = messages.map((m) => m.content || "").join(" ");
    const promptTokens = usageTracker.estimateTokens(promptText);
    const completionTokens = usageTracker.estimateTokens(content);
    usageTracker.addUsage(promptTokens, completionTokens);

    return {
      message: {
        role: "assistant",
        content: content || null,
        tool_calls: toolCalls.length > 0 ? toolCalls : undefined,
      },
      usage: { promptTokens, completionTokens, totalTokens: promptTokens + completionTokens },
    };
  }
}

