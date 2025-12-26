/**
 * Anthropic LLM Provider
 *
 * Cloud-based provider using Anthropic's API for access to Claude models.
 */

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
};

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function getRetryDelay(attempt: number): number {
  const delay = RETRY_CONFIG.baseDelayMs * Math.pow(2, attempt);
  return Math.min(delay, RETRY_CONFIG.maxDelayMs);
}

function isRetryableError(error: unknown): boolean {
  if (error instanceof Error) {
    const message = error.message.toLowerCase();
    if (message.includes("rate limit") || message.includes("overloaded") || message.includes("529")) {
      return true;
    }
  }
  return false;
}

// Default Anthropic models
const DEFAULT_ANTHROPIC_MODELS = [
  "claude-sonnet-4-20250514",
  "claude-opus-4-20250514",
  "claude-3-5-sonnet-20241022",
  "claude-3-5-haiku-20241022",
] as const;

export class AnthropicProvider implements LLMProvider {
  private apiKey: string;
  private defaultModel: string;

  readonly info: ProviderInfo;

  constructor(
    apiKey: string,
    defaultModel: string = "claude-sonnet-4-20250514",
    customModels?: readonly string[]
  ) {
    this.apiKey = apiKey;
    this.defaultModel = defaultModel;
    this.info = {
      id: "anthropic",
      name: "Anthropic",
      description: "Cloud-based access to Anthropic Claude models",
      capabilities: {
        streaming: true,
        toolCalling: true,
        structuredOutput: true,
        embeddings: false,
        local: false,
      },
      availableModels: customModels ?? DEFAULT_ANTHROPIC_MODELS,
    };
  }

  async checkAvailability(): Promise<ProviderStatus> {
    if (!this.apiKey) {
      return { available: false, reason: "No API key configured" };
    }
    return { available: true, model: this.defaultModel };
  }

  async initialize(): Promise<void> {
    // No initialization needed
  }

  async chat(messages: Message[], options?: ChatOptions): Promise<ChatResponse> {
    const model = options?.model || this.defaultModel;
    let lastError: Error | undefined;

    for (let attempt = 0; attempt <= RETRY_CONFIG.maxRetries; attempt++) {
      try {
        return await this.doChat(messages, model, options);
      } catch (error) {
        lastError = error instanceof Error ? error : new Error(String(error));
        if (attempt < RETRY_CONFIG.maxRetries && isRetryableError(error)) {
          await sleep(getRetryDelay(attempt));
          continue;
        }
        throw lastError;
      }
    }
    throw lastError ?? new Error("Unexpected retry loop exit");
  }

  private async doChat(messages: Message[], model: string, options?: ChatOptions): Promise<ChatResponse> {
    // Extract system message and convert to Anthropic format
    let systemPrompt: string | undefined;
    const anthropicMessages: Array<{ role: string; content: unknown }> = [];

    for (const msg of messages) {
      if (msg.role === "system") {
        systemPrompt = (systemPrompt ? systemPrompt + "\n\n" : "") + (msg.content || "");
      } else if (msg.role === "user") {
        anthropicMessages.push({ role: "user", content: msg.content || "" });
      } else if (msg.role === "assistant") {
        if (msg.tool_calls && msg.tool_calls.length > 0) {
          const content: unknown[] = [];
          if (msg.content) {
            content.push({ type: "text", text: msg.content });
          }
          for (const tc of msg.tool_calls) {
            // Safely parse tool arguments, fallback to empty object on malformed JSON
            let parsedInput: unknown = {};
            try {
              parsedInput = JSON.parse(tc.function.arguments);
            } catch {
              // Malformed JSON in tool arguments - use empty object
            }
            content.push({
              type: "tool_use",
              id: tc.id,
              name: tc.function.name,
              input: parsedInput,
            });
          }
          anthropicMessages.push({ role: "assistant", content });
        } else {
          anthropicMessages.push({ role: "assistant", content: msg.content || "" });
        }
      } else if (msg.role === "tool") {
        anthropicMessages.push({
          role: "user",
          content: [{ type: "tool_result", tool_use_id: msg.tool_call_id, content: msg.content || "" }],
        });
      }
    }

    const body: Record<string, unknown> = {
      model,
      max_tokens: options?.maxTokens || 4096,
      messages: anthropicMessages,
      stream: true,
    };

    if (systemPrompt) {
      body.system = systemPrompt;
    }
    if (options?.tools && options.tools.length > 0) {
      body.tools = options.tools.map((t) => ({
        name: t.function.name,
        description: t.function.description,
        input_schema: t.function.parameters,
      }));
    }
    if (options?.temperature !== undefined) {
      body.temperature = options.temperature;
    }

    const response = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": this.apiKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify(body),
    });

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`Anthropic API error: ${response.status} ${errorText}`);
    }

    return this.processStream(response, messages, options?.onChunk);
  }

  private async processStream(
    response: Response,
    messages: Message[],
    onChunk?: (content: string) => void
  ): Promise<ChatResponse> {
    const reader = response.body?.getReader();
    if (!reader) throw new Error("No response body");

    const decoder = new TextDecoder();
    let content = "";
    const toolCalls: Array<{ id: string; type: "function"; function: { name: string; arguments: string } }> = [];
    let currentToolUse: { id: string; name: string; input: string } | null = null;
    let buffer = "";

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split("\n");
      buffer = lines.pop() || "";

      for (const line of lines) {
        if (!line.startsWith("data: ")) continue;

        try {
          const data = JSON.parse(line.slice(6));

          if (data.type === "content_block_start") {
            if (data.content_block?.type === "tool_use") {
              currentToolUse = {
                id: data.content_block.id,
                name: data.content_block.name,
                input: "",
              };
            }
          } else if (data.type === "content_block_delta") {
            if (data.delta?.type === "text_delta" && data.delta.text) {
              content += data.delta.text;
              onChunk?.(data.delta.text);
            } else if (data.delta?.type === "input_json_delta" && currentToolUse) {
              currentToolUse.input += data.delta.partial_json || "";
            }
          } else if (data.type === "content_block_stop" && currentToolUse) {
            toolCalls.push({
              id: currentToolUse.id,
              type: "function",
              function: {
                name: currentToolUse.name,
                arguments: currentToolUse.input,
              },
            });
            currentToolUse = null;
          }
        } catch {
          // Skip malformed JSON
        }
      }
    }

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
