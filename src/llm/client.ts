import { OpenRouter } from "@openrouter/sdk";
import { config } from "../config/index.ts";
import type { Message, ToolDefinition } from "./types.ts";
import { usageTracker } from "./usage.ts";

// Retry configuration
const RETRY_CONFIG = {
  maxRetries: 3,
  baseDelayMs: 1000,
  maxDelayMs: 10000,
  retryableStatusCodes: [429, 500, 502, 503, 504],
};

/**
 * Sleep for a given number of milliseconds
 */
function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Calculate exponential backoff delay with jitter
 */
function getRetryDelay(attempt: number): number {
  const exponentialDelay = RETRY_CONFIG.baseDelayMs * Math.pow(2, attempt);
  const jitter = Math.random() * 0.3 * exponentialDelay; // 0-30% jitter
  return Math.min(exponentialDelay + jitter, RETRY_CONFIG.maxDelayMs);
}

/**
 * Check if an error is retryable
 */
function isRetryableError(error: unknown): boolean {
  if (error instanceof Error) {
    // Check for rate limit or server errors in message
    const message = error.message.toLowerCase();
    if (message.includes("rate limit") || message.includes("too many requests")) {
      return true;
    }
    if (message.includes("timeout") || message.includes("timed out")) {
      return true;
    }
    if (message.includes("network") || message.includes("connection")) {
      return true;
    }
    // Check for HTTP status codes in error
    for (const code of RETRY_CONFIG.retryableStatusCodes) {
      if (message.includes(String(code))) {
        return true;
      }
    }
  }
  return false;
}

// Type for streaming chunk from OpenRouter SDK
interface SDKStreamChunk {
  id: string;
  choices: Array<{
    delta: {
      role?: string;
      content?: string | null;
      toolCalls?: Array<{
        index?: number;
        id?: string;
        function?: {
          name?: string;
          arguments?: string;
        };
      }>;
    };
    finishReason: string | null;
    index: number;
  }>;
}

/**
 * Transform our Message format to SDK format (snake_case -> camelCase)
 */
function transformMessagesForSDK(messages: Message[]): Parameters<OpenRouter["chat"]["send"]>[0]["messages"] {
  return messages.map((msg) => {
    if (msg.role === "tool") {
      return {
        role: "tool" as const,
        content: msg.content || "",
        toolCallId: msg.tool_call_id || "",
      };
    }
    if (msg.role === "assistant" && msg.tool_calls) {
      return {
        role: "assistant" as const,
        content: msg.content,
        toolCalls: msg.tool_calls.map((tc) => ({
          id: tc.id,
          type: "function" as const,
          function: tc.function,
        })),
      };
    }
    return {
      role: msg.role,
      content: msg.content || "",
    };
  }) as Parameters<OpenRouter["chat"]["send"]>[0]["messages"];
}

/**
 * OpenRouter client wrapper for Clarissa
 */
class LLMClient {
  private client: OpenRouter;

  constructor() {
    this.client = new OpenRouter({
      apiKey: config.OPENROUTER_API_KEY,
    });
  }

  /**
   * Send a chat completion request (non-streaming) with retry logic
   */
  async chat(
    messages: Message[],
    tools?: ToolDefinition[],
    model?: string
  ): Promise<Message> {
    let lastError: Error | undefined;

    for (let attempt = 0; attempt <= RETRY_CONFIG.maxRetries; attempt++) {
      try {
        const response = await this.client.chat.send({
          model: model || config.OPENROUTER_MODEL,
          messages: transformMessagesForSDK(messages),
          tools: tools as Parameters<typeof this.client.chat.send>[0]["tools"],
        });

        const choice = response.choices?.[0];
        if (!choice) {
          throw new Error("No response from LLM");
        }

        // Convert SDK toolCalls to our format
        const toolCalls = choice.message?.toolCalls?.map((tc) => ({
          id: tc.id,
          type: "function" as const,
          function: {
            name: tc.function.name,
            arguments: tc.function.arguments,
          },
        }));

        return {
          role: "assistant",
          content: typeof choice.message?.content === "string" ? choice.message.content : null,
          tool_calls: toolCalls && toolCalls.length > 0 ? toolCalls : undefined,
        };
      } catch (error) {
        lastError = error instanceof Error ? error : new Error(String(error));

        if (attempt < RETRY_CONFIG.maxRetries && isRetryableError(error)) {
          const delay = getRetryDelay(attempt);
          await sleep(delay);
          continue;
        }

        throw lastError;
      }
    }

    throw lastError ?? new Error("Unexpected retry loop exit");
  }

  /**
   * Accumulate streaming chunks into a complete message with retry logic
   */
  async chatStreamComplete(
    messages: Message[],
    tools?: ToolDefinition[],
    model?: string,
    onChunk?: (content: string) => void
  ): Promise<Message> {
    let lastError: Error | undefined;

    for (let attempt = 0; attempt <= RETRY_CONFIG.maxRetries; attempt++) {
      try {
        const stream = await this.client.chat.send({
          model: model || config.OPENROUTER_MODEL,
          messages: transformMessagesForSDK(messages),
          tools: tools as Parameters<typeof this.client.chat.send>[0]["tools"],
          stream: true,
        });

        let content = "";
        const toolCallsMap: Map<number, {
          id: string;
          type: "function";
          function: { name: string; arguments: string };
        }> = new Map();

        for await (const rawChunk of stream) {
          const chunk = rawChunk as unknown as SDKStreamChunk;
          const delta = chunk.choices?.[0]?.delta;
          if (!delta) continue;

          // Handle content
          if (delta.content) {
            content += delta.content;
            onChunk?.(delta.content);
          }

          // Handle tool calls (SDK uses camelCase: toolCalls)
          if (delta.toolCalls) {
            for (const tc of delta.toolCalls) {
              const index = tc.index ?? 0;

              if (tc.id) {
                // New tool call starting
                toolCallsMap.set(index, {
                  id: tc.id,
                  type: "function",
                  function: {
                    name: tc.function?.name || "",
                    arguments: tc.function?.arguments || "",
                  },
                });
              } else if (tc.function) {
                // Continuing existing tool call
                const existing = toolCallsMap.get(index);
                if (existing) {
                  if (tc.function.name) {
                    existing.function.name += tc.function.name;
                  }
                  if (tc.function.arguments) {
                    existing.function.arguments += tc.function.arguments;
                  }
                }
              }
            }
          }
        }

        const toolCalls = Array.from(toolCallsMap.values());

        // Estimate token usage for streaming (rough approximation)
        const promptText = messages.map((m) => m.content || "").join(" ");
        const promptTokens = usageTracker.estimateTokens(promptText);
        const completionTokens = usageTracker.estimateTokens(content);
        usageTracker.addUsage(promptTokens, completionTokens);

        return {
          role: "assistant",
          content: content || null,
          tool_calls: toolCalls.length > 0 ? toolCalls : undefined,
        };
      } catch (error) {
        lastError = error instanceof Error ? error : new Error(String(error));

        if (attempt < RETRY_CONFIG.maxRetries && isRetryableError(error)) {
          const delay = getRetryDelay(attempt);
          await sleep(delay);
          continue;
        }

        throw lastError;
      }
    }

    throw lastError ?? new Error("Unexpected retry loop exit");
  }
}

export const llmClient = new LLMClient();
export { usageTracker } from "./usage.ts";

