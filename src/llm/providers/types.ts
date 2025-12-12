/**
 * LLM Provider abstraction types
 *
 * This module defines the common interface that all LLM providers must implement,
 * allowing Clarissa to work with multiple backends (OpenRouter, LM Studio, local models, etc.)
 */

import type { Message, ToolDefinition } from "../types.ts";

/**
 * Provider capability flags
 */
export interface ProviderCapabilities {
  /** Supports streaming responses */
  streaming: boolean;
  /** Supports tool/function calling */
  toolCalling: boolean;
  /** Supports structured JSON output */
  structuredOutput: boolean;
  /** Supports embeddings */
  embeddings: boolean;
  /** Runs locally (no internet required) */
  local: boolean;
  /** Maximum number of tools the provider can handle effectively (undefined = unlimited) */
  maxTools?: number;
}

/**
 * Provider availability status
 */
export interface ProviderStatus {
  available: boolean;
  reason?: string;
  model?: string;
  /** Additional metadata about the provider */
  metadata?: {
    /** Model file size in MB */
    fileSizeMB?: number;
    /** Estimated memory required in MB */
    estimatedMemoryMB?: number;
    /** Context window size */
    contextSize?: number;
  };
}

/**
 * Provider metadata
 */
export interface ProviderInfo {
  /** Unique provider identifier */
  id: string;
  /** Human-readable name */
  name: string;
  /** Provider description */
  description: string;
  /** Provider capabilities */
  capabilities: ProviderCapabilities;
  /** Available models for this provider (undefined if not selectable) */
  availableModels?: readonly string[];
}

/**
 * Chat request options
 */
export interface ChatOptions {
  /** Model to use (provider-specific format) */
  model?: string;
  /** Tool definitions for function calling */
  tools?: ToolDefinition[];
  /** Callback for streaming chunks */
  onChunk?: (content: string) => void;
  /** Temperature for response generation */
  temperature?: number;
  /** Maximum tokens to generate */
  maxTokens?: number;
}

/**
 * Chat response with usage statistics
 */
export interface ChatResponse {
  message: Message;
  usage?: {
    promptTokens: number;
    completionTokens: number;
    totalTokens: number;
  };
}

/**
 * Common interface for all LLM providers
 */
export interface LLMProvider {
  /** Provider information */
  readonly info: ProviderInfo;

  /**
   * Check if the provider is available and ready to use
   */
  checkAvailability(): Promise<ProviderStatus>;

  /**
   * Send a chat completion request
   * @param messages - Conversation messages
   * @param options - Request options
   * @returns The assistant's response message
   */
  chat(messages: Message[], options?: ChatOptions): Promise<ChatResponse>;

  /**
   * Initialize the provider (load models, connect to servers, etc.)
   * Called once before first use
   * @param onProgress - Optional callback for initialization progress (0-1)
   */
  initialize?(onProgress?: (progress: number) => void): Promise<void>;

  /**
   * Clean up resources (unload models, disconnect, etc.)
   */
  shutdown?(): Promise<void>;

  /**
   * Prewarm the model for faster first response (iOS pattern)
   * This is an optional optimization that some providers support.
   * Call early (e.g., during startup) for better UX on first interaction.
   */
  prewarm?(): Promise<void>;

  /**
   * Generate embeddings for the given texts
   * Only available if capabilities.embeddings is true
   * @param texts - Array of texts to embed
   * @returns Array of embedding vectors
   */
  embed?(texts: string[]): Promise<number[][]>;
}

/**
 * Provider constructor type
 */
export type ProviderConstructor = new () => LLMProvider;

/**
 * Provider priority for auto-selection (lower = higher priority)
 */
export const PROVIDER_PRIORITY = {
  openrouter: 1, // Cloud provider - use if API key available
  openai: 2, // OpenAI direct API
  anthropic: 3, // Anthropic direct API
  "apple-ai": 4, // Apple on-device (highest priority local)
  lmstudio: 5, // Local with nice UX
  ollama: 6, // Local server
  "local-llama": 7, // Direct local inference
} as const;

export type ProviderId = keyof typeof PROVIDER_PRIORITY;

