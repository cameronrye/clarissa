/**
 * LLM Client for Clarissa
 *
 * This module provides a unified interface for LLM operations,
 * supporting multiple providers (OpenRouter, LM Studio, local models).
 */

import { config, getLocalLlamaConfig, getProviderModels } from "../config/index.ts";
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
 * LLM Client that uses the provider abstraction
 */
class LLMClient {
  private provider: LLMProvider | null = null;
  private initPromise: Promise<void> | null = null;

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
   * Send a chat completion request (non-streaming)
   */
  async chat(
    messages: Message[],
    tools?: ToolDefinition[],
    model?: string
  ): Promise<Message> {
    const provider = await this.ensureProvider();
    const response = await provider.chat(messages, { model, tools });
    return response.message;
  }

  /**
   * Accumulate streaming chunks into a complete message
   */
  async chatStreamComplete(
    messages: Message[],
    tools?: ToolDefinition[],
    model?: string,
    onChunk?: (content: string) => void
  ): Promise<Message> {
    const provider = await this.ensureProvider();
    const response = await provider.chat(messages, { model, tools, onChunk });
    return response.message;
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

