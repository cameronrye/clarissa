/**
 * LLM Client for Clarissa
 *
 * This module provides a unified interface for LLM operations,
 * supporting multiple providers (OpenRouter, LM Studio, local models).
 * Includes automatic fallback to backup models on failure.
 */

import { config, getLocalLlamaConfig, getProviderModels, getFallbackConfig, type FallbackConfig } from "../config/index.ts";
import type { Message, ToolDefinition } from "./types.ts";
import { providerRegistry, type LLMProvider, type ProviderId } from "./providers/index.ts";

// Get custom model lists from config
const providerModels = getProviderModels();

// Initialize provider registry with config
providerRegistry.configure({
  openrouterApiKey: config.OPENROUTER_API_KEY,
  openrouterModel: config.OPENROUTER_MODEL,
  openrouterModels: providerModels.openrouter,
  openaiApiKey: config.OPENAI_API_KEY,
  openaiModel: config.OPENAI_MODEL,
  openaiModels: providerModels.openai,
  anthropicApiKey: config.ANTHROPIC_API_KEY,
  anthropicModel: config.ANTHROPIC_MODEL,
  anthropicModels: providerModels.anthropic,
  preferredProvider: config.PROVIDER as ProviderId | undefined,
  lmstudioModel: config.LMSTUDIO_MODEL,
  localModelPath: config.LOCAL_MODEL_PATH,
  localLlamaConfig: getLocalLlamaConfig(),
});

/**
 * Default fallback models when none configured
 * Uses cloud providers with high availability
 */
const DEFAULT_FALLBACK_MODELS = [
  "openrouter:anthropic/claude-sonnet-4",
  "openrouter:openai/gpt-4o",
  "openai:gpt-4o",
  "anthropic:claude-sonnet-4",
];

/**
 * Error types that trigger fallback
 */
type FallbackErrorType = "rate_limit" | "timeout" | "server_error" | "all";

/**
 * Check if an error should trigger fallback
 */
function shouldFallback(error: Error, errorTypes: FallbackErrorType[]): boolean {
  if (errorTypes.includes("all")) return true;

  const message = error.message.toLowerCase();

  if (errorTypes.includes("rate_limit")) {
    if (message.includes("rate") || message.includes("429") || message.includes("too many")) {
      return true;
    }
  }

  if (errorTypes.includes("timeout")) {
    if (message.includes("timeout") || message.includes("timed out") || message.includes("etimedout")) {
      return true;
    }
  }

  if (errorTypes.includes("server_error")) {
    if (message.includes("500") || message.includes("502") || message.includes("503") ||
        message.includes("server error") || message.includes("internal error")) {
      return true;
    }
  }

  return false;
}

/**
 * Parse a fallback model string into provider and model
 * Format: "provider:model" or just "provider" for local providers
 */
function parseFallbackModel(modelSpec: string): { providerId: ProviderId; model?: string } {
  const colonIndex = modelSpec.indexOf(":");
  if (colonIndex === -1) {
    // Just a provider ID (for local providers like apple-ai, lmstudio, local-llama)
    return { providerId: modelSpec as ProviderId };
  }
  const providerId = modelSpec.slice(0, colonIndex) as ProviderId;
  const model = modelSpec.slice(colonIndex + 1);
  return { providerId, model };
}

/**
 * LLM Client that uses the provider abstraction
 * Supports automatic fallback to backup models on failure
 */
class LLMClient {
  private provider: LLMProvider | null = null;
  private initPromise: Promise<void> | null = null;
  private fallbackConfig: FallbackConfig | undefined;
  private onFallback?: (from: string, to: string, error: string) => void;

  constructor() {
    this.fallbackConfig = getFallbackConfig();
  }

  /**
   * Set a callback to be notified when fallback occurs
   */
  setFallbackCallback(callback: (from: string, to: string, error: string) => void): void {
    this.onFallback = callback;
  }

  /**
   * Ensure provider is initialized
   */
  private async ensureProvider(): Promise<LLMProvider> {
    if (this.provider) return this.provider;

    if (!this.initPromise) {
      this.initPromise = (async () => {
        try {
          this.provider = await providerRegistry.getActiveProvider();
        } catch (error) {
          // Reset initPromise on failure so retry is possible
          this.initPromise = null;
          throw error;
        }
      })();
    }

    await this.initPromise;

    if (!this.provider) {
      throw new Error("Failed to initialize LLM provider");
    }

    return this.provider;
  }

  /**
   * Try to get a fallback provider
   */
  private async tryFallbackProvider(
    currentProviderId: string,
    attemptIndex: number
  ): Promise<{ provider: LLMProvider; model?: string } | null> {
    const fallbackModels = this.fallbackConfig?.models ?? DEFAULT_FALLBACK_MODELS;
    const maxAttempts = this.fallbackConfig?.maxAttempts ?? 2;

    if (attemptIndex >= maxAttempts || attemptIndex >= fallbackModels.length) {
      return null;
    }

    // Try each fallback model in order, skipping the current provider
    for (let i = attemptIndex; i < Math.min(fallbackModels.length, maxAttempts); i++) {
      const { providerId, model } = parseFallbackModel(fallbackModels[i]!);

      // Skip if same as current provider (unless it's a different model)
      if (providerId === currentProviderId && !model) continue;

      try {
        const provider = providerRegistry.getProvider(providerId);
        if (!provider) continue;

        const status = await provider.checkAvailability();
        if (status.available) {
          await provider.initialize?.();
          return { provider, model };
        }
      } catch {
        // Provider not available, try next
        continue;
      }
    }

    return null;
  }

  /**
   * Execute a chat request with automatic fallback on failure
   */
  private async chatWithFallback(
    messages: Message[],
    options: { model?: string; tools?: ToolDefinition[]; onChunk?: (content: string) => void }
  ): Promise<Message> {
    const provider = await this.ensureProvider();
    const fallbackEnabled = this.fallbackConfig?.enabled !== false;
    const errorTypes = this.fallbackConfig?.onErrors ?? ["rate_limit", "timeout"];

    let lastError: Error | undefined;
    let currentProvider = provider;
    let currentModel = options.model;

    // Try primary provider first
    try {
      const response = await currentProvider.chat(messages, { ...options, model: currentModel });
      return response.message;
    } catch (error) {
      lastError = error instanceof Error ? error : new Error(String(error));

      // Check if we should fallback
      if (!fallbackEnabled || !shouldFallback(lastError, errorTypes as FallbackErrorType[])) {
        throw lastError;
      }

      if (process.env.DEBUG) {
        console.log(`[Fallback] Primary provider failed: ${lastError.message}`);
      }
    }

    // Try fallback providers
    const maxAttempts = this.fallbackConfig?.maxAttempts ?? 2;
    for (let attempt = 0; attempt < maxAttempts; attempt++) {
      const fallback = await this.tryFallbackProvider(currentProvider.info.id, attempt);
      if (!fallback) break;

      const { provider: fallbackProvider, model: fallbackModel } = fallback;
      const fromProvider = `${currentProvider.info.id}${currentModel ? `:${currentModel}` : ""}`;
      const toProvider = `${fallbackProvider.info.id}${fallbackModel ? `:${fallbackModel}` : ""}`;

      if (process.env.DEBUG) {
        console.log(`[Fallback] Trying ${toProvider} (attempt ${attempt + 1})`);
      }

      this.onFallback?.(fromProvider, toProvider, lastError?.message ?? "Unknown error");

      try {
        const response = await fallbackProvider.chat(messages, {
          ...options,
          model: fallbackModel,
        });
        return response.message;
      } catch (error) {
        lastError = error instanceof Error ? error : new Error(String(error));
        currentProvider = fallbackProvider;
        currentModel = fallbackModel;

        if (!shouldFallback(lastError, errorTypes as FallbackErrorType[])) {
          throw lastError;
        }
      }
    }

    // All fallbacks failed
    throw lastError ?? new Error("All LLM providers failed");
  }

  /**
   * Get the current provider info
   */
  async getProviderInfo(): Promise<{ id: string; name: string }> {
    const provider = await this.ensureProvider();
    return { id: provider.info.id, name: provider.info.name };
  }

  /**
   * Get the maximum number of tools the current provider can handle
   * Returns undefined if no limit
   */
  async getMaxTools(): Promise<number | undefined> {
    const provider = await this.ensureProvider();
    return provider.info.capabilities.maxTools;
  }

  /**
   * Send a chat completion request (non-streaming) with fallback support
   */
  async chat(
    messages: Message[],
    tools?: ToolDefinition[],
    model?: string
  ): Promise<Message> {
    return this.chatWithFallback(messages, { model, tools });
  }

  /**
   * Accumulate streaming chunks into a complete message with fallback support
   */
  async chatStreamComplete(
    messages: Message[],
    tools?: ToolDefinition[],
    model?: string,
    onChunk?: (content: string) => void
  ): Promise<Message> {
    return this.chatWithFallback(messages, { model, tools, onChunk });
  }

  /**
   * Prewarm the current provider's model for faster first response (iOS pattern)
   * This is an optional optimization that some providers (like Apple AI) support.
   * Call early (e.g., during startup) for better UX on first interaction.
   */
  async prewarm(): Promise<void> {
    try {
      const provider = await this.ensureProvider();
      if (provider.prewarm) {
        await provider.prewarm();
      }
    } catch {
      // Silently fail prewarm - it's just an optimization
    }
  }

  /**
   * Switch to a different provider
   */
  async switchProvider(providerId: ProviderId): Promise<void> {
    await providerRegistry.setActiveProvider(providerId);
    this.provider = await providerRegistry.getActiveProvider();
    this.initPromise = null;
  }

  /**
   * Get available providers and their status
   */
  async getAvailableProviders(): Promise<
    Array<{ id: ProviderId; name: string; available: boolean; reason?: string }>
  > {
    const statuses = await providerRegistry.getProviderStatuses();
    const providers = providerRegistry.getRegisteredProviders();

    return providers.map((p) => {
      const status = statuses.get(p.id);
      return {
        id: p.id,
        name: p.name,
        available: status?.available ?? false,
        reason: status?.reason,
      };
    });
  }
}

export const llmClient = new LLMClient();
export { usageTracker } from "./usage.ts";
export { providerRegistry } from "./providers/index.ts";

