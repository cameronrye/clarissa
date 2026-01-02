import { z } from "zod";
import { homedir } from "os";
import { join } from "path";
import { mkdirSync, existsSync, readFileSync } from "fs";

export const CONFIG_DIR = join(homedir(), ".clarissa");
export const CONFIG_FILE = join(CONFIG_DIR, "config.json");

/**
 * API keys for cloud providers
 */
export interface ApiKeys {
  openrouterApiKey?: string;
  openaiApiKey?: string;
  anthropicApiKey?: string;
}

/**
 * Initialize config by creating directory and saving API keys
 */
export async function initConfig(keys: ApiKeys): Promise<void> {
  if (!existsSync(CONFIG_DIR)) {
    mkdirSync(CONFIG_DIR, { recursive: true });
  }

  // Load existing config to preserve other settings
  let existingConfig: Record<string, unknown> = {};
  try {
    if (existsSync(CONFIG_FILE)) {
      existingConfig = JSON.parse(await Bun.file(CONFIG_FILE).text());
    }
  } catch {
    // Ignore parse errors, start fresh
  }

  // Merge new keys with existing config, only setting non-empty values
  const newConfig = { ...existingConfig };
  if (keys.openrouterApiKey) newConfig.openrouterApiKey = keys.openrouterApiKey;
  if (keys.openaiApiKey) newConfig.openaiApiKey = keys.openaiApiKey;
  if (keys.anthropicApiKey) newConfig.anthropicApiKey = keys.anthropicApiKey;

  await Bun.write(CONFIG_FILE, JSON.stringify(newConfig, null, 2) + "\n");
}

/**
 * Check if config file exists with at least one API key
 */
export function hasApiKey(): boolean {
  try {
    if (!existsSync(CONFIG_FILE)) return false;
    // Use readFileSync + JSON.parse instead of require() for consistency
    // require() caches results and is unusual in ESM context
    const content = JSON.parse(readFileSync(CONFIG_FILE, "utf-8"));
    return Boolean(
      content?.openrouterApiKey ||
      content?.openaiApiKey ||
      content?.anthropicApiKey
    );
  } catch {
    return false;
  }
}

/**
 * MCP server configuration schema (standard MCP JSON format)
 * Supports two transport types:
 * - stdio: Local process with command/args
 * - sse: Remote HTTP/SSE server with URL
 */
const mcpServerStdioSchema = z.object({
  transport: z.literal("stdio").optional(), // Default transport
  command: z.string(),
  args: z.array(z.string()).optional(),
  env: z.record(z.string(), z.string()).optional(),
});

const mcpServerSseSchema = z.object({
  transport: z.literal("sse"),
  url: z.string().url(),
  headers: z.record(z.string(), z.string()).optional(),
});

const mcpServerSchema = z.union([mcpServerStdioSchema, mcpServerSseSchema]);

export type MCPServerStdioConfig = z.infer<typeof mcpServerStdioSchema>;
export type MCPServerSseConfig = z.infer<typeof mcpServerSseSchema>;
export type MCPServerFileConfig = z.infer<typeof mcpServerSchema>;

/**
 * Valid provider IDs
 */
const providerIdSchema = z.enum(["openrouter", "openai", "anthropic", "apple-ai", "lmstudio", "local-llama"]);
export type ProviderIdConfig = z.infer<typeof providerIdSchema>;

/**
 * Local Llama configuration schema
 */
const localLlamaConfigSchema = z.object({
  /** Path to the GGUF model file */
  modelPath: z.string(),
  /** Number of layers to offload to GPU (-1 for auto, 0 for CPU-only) */
  gpuLayers: z.number().int().min(-1).optional(),
  /** Context window size in tokens */
  contextSize: z.number().int().positive().optional(),
  /** Batch size for prompt processing */
  batchSize: z.number().int().positive().optional(),
  /** Enable flash attention for faster inference */
  flashAttention: z.boolean().optional(),
});

export type LocalLlamaFileConfig = z.infer<typeof localLlamaConfigSchema>;

// Store loaded local-llama config for access by other modules
let loadedLocalLlamaConfig: LocalLlamaFileConfig | undefined;

/**
 * Get configured local-llama settings from config file
 */
export function getLocalLlamaConfig(): LocalLlamaFileConfig | undefined {
  return loadedLocalLlamaConfig;
}

/**
 * Provider-specific models configuration
 */
const providerModelsSchema = z.object({
  openrouter: z.array(z.string()).optional(),
  openai: z.array(z.string()).optional(),
  anthropic: z.array(z.string()).optional(),
});

export type ProviderModelsConfig = z.infer<typeof providerModelsSchema>;

/**
 * Fallback model configuration
 * Defines backup models to try when the primary model fails
 */
const fallbackConfigSchema = z.object({
  /** Enable automatic fallback on errors */
  enabled: z.boolean().default(true),
  /** Maximum number of fallback attempts */
  maxAttempts: z.number().int().min(1).max(5).default(2),
  /** Ordered list of fallback models (provider/model format for cloud, or provider ID for local) */
  models: z.array(z.string()).optional(),
  /** Error types that trigger fallback (rate_limit, timeout, server_error, all) */
  onErrors: z.array(z.enum(["rate_limit", "timeout", "server_error", "all"])).default(["rate_limit", "timeout"]),
});

export type FallbackConfig = z.infer<typeof fallbackConfigSchema>;

// Store loaded fallback config
let loadedFallbackConfig: FallbackConfig | undefined;

/**
 * Get fallback configuration
 */
export function getFallbackConfig(): FallbackConfig | undefined {
  return loadedFallbackConfig;
}

/**
 * Config file schema
 */
const configFileSchema = z.object({
  // Cloud provider API keys
  openrouterApiKey: z.string().min(1).optional(),
  openaiApiKey: z.string().min(1).optional(),
  anthropicApiKey: z.string().min(1).optional(),
  // General settings
  maxIterations: z.number().int().positive().optional(),
  debug: z.boolean().optional(),
  mcpServers: z.record(z.string(), mcpServerSchema).optional(),
  // Local LLM settings
  lmstudioModel: z.string().optional(),
  localModelPath: z.string().optional(),
  // Local Llama advanced configuration (alternative to just localModelPath)
  localLlama: localLlamaConfigSchema.optional(),
  // Custom model lists per provider
  models: providerModelsSchema.optional(),
  // Fallback model configuration
  fallback: fallbackConfigSchema.optional(),
});

type ConfigFile = z.infer<typeof configFileSchema>;

// Store loaded MCP servers config for access by other modules
let loadedMcpServers: Record<string, MCPServerFileConfig> = {};

/**
 * Get configured MCP servers from config file
 */
export function getMcpServers(): Record<string, MCPServerFileConfig> {
  return loadedMcpServers;
}

// Store loaded provider models config for access by other modules
let loadedProviderModels: ProviderModelsConfig = {};

/**
 * Get configured model lists per provider from config file
 */
export function getProviderModels(): ProviderModelsConfig {
  return loadedProviderModels;
}

/**
 * Environment configuration schema with Zod validation
 */
const envSchema = z.object({
  // OpenRouter API key is now optional (local providers don't need it)
  OPENROUTER_API_KEY: z.string().optional(),
  OPENROUTER_MODEL: z.string().default("anthropic/claude-sonnet-4"),
  // OpenAI direct API
  OPENAI_API_KEY: z.string().optional(),
  OPENAI_MODEL: z.string().default("gpt-4o"),
  // Anthropic direct API
  ANTHROPIC_API_KEY: z.string().optional(),
  ANTHROPIC_MODEL: z.string().default("claude-sonnet-4-20250514"),
  APP_NAME: z.string().default("Clarissa"),
  APP_URL: z.string().url().optional(),
  MAX_ITERATIONS: z.coerce.number().int().positive().default(10),
  DEBUG: z
    .string()
    .optional()
    .default("false")
    .transform((val) => val === "true" || val === "1"),
  // Provider settings from config file (passed through env for consistency)
  PROVIDER: providerIdSchema.optional(),
  LMSTUDIO_MODEL: z.string().optional(),
  LOCAL_MODEL_PATH: z.string().optional(),
});

export type EnvConfig = z.infer<typeof envSchema>;

/**
 * Check if we're running in a test environment
 */
const isTestEnv = process.env.NODE_ENV === "test" || typeof Bun !== "undefined" && Bun.env.BUN_ENV === "test" || process.argv.some(arg => arg.includes("bun") && arg.includes("test"));

const PREFERENCES_FILE = join(CONFIG_DIR, "preferences.json");

/**
 * Preferences schema for saved runtime settings
 */
interface SavedPreferences {
  lastProvider?: ProviderIdConfig;
  lastModel?: string;
}

// Store loaded preferences for access by other modules
let loadedPreferences: SavedPreferences = {};

/**
 * Load preferences from ~/.clarissa/preferences.json (synchronous)
 */
function loadPreferencesFile(): SavedPreferences {
  try {
    if (!existsSync(PREFERENCES_FILE)) return {};
    const content = require(PREFERENCES_FILE);
    return {
      lastProvider: content?.lastProvider,
      lastModel: content?.lastModel,
    };
  } catch {
    return {};
  }
}

/**
 * Get loaded preferences
 */
export function getPreferences(): SavedPreferences {
  return loadedPreferences;
}

/**
 * Load config from ~/.clarissa/config.json
 */
function loadConfigFile(): ConfigFile | null {
  try {
    const file = Bun.file(CONFIG_FILE);
    if (!file.size) return null;
    const content = require(CONFIG_FILE);
    const result = configFileSchema.safeParse(content);
    if (result.success) {
      // Store MCP servers for later access
      loadedMcpServers = result.data.mcpServers || {};
      // Store local-llama config for later access
      if (result.data.localLlama) {
        loadedLocalLlamaConfig = result.data.localLlama;
      } else if (result.data.localModelPath) {
        // Support legacy localModelPath as simple config
        loadedLocalLlamaConfig = { modelPath: result.data.localModelPath };
      }
      // Store provider models for later access
      loadedProviderModels = result.data.models || {};
      // Store fallback config for later access
      loadedFallbackConfig = result.data.fallback;
      return result.data;
    }
    return null;
  } catch {
    return null;
  }
}

/**
 * Show setup instructions when no provider is configured
 */
function showSetupInstructions(): never {
  console.error(`
No LLM provider configured. Options:

1. Cloud (OpenRouter):
   clarissa init
   Or: export OPENROUTER_API_KEY=your_api_key_here

2. Local (LM Studio):
   - Install LM Studio from https://lmstudio.ai
   - Load a model and start the server
   - Clarissa will auto-detect it

3. Local (Direct GGUF model):
   - Add to ~/.clarissa/config.json:
     { "localModelPath": "/path/to/model.gguf" }
`);
  process.exit(1);
}

/**
 * Validate and parse environment variables
 */
function loadConfig(): EnvConfig {
  // In test environment, use defaults if API key not provided
  if (isTestEnv && !process.env.OPENROUTER_API_KEY) {
    return {
      OPENROUTER_API_KEY: "test-api-key",
      OPENROUTER_MODEL: "anthropic/claude-sonnet-4",
      OPENAI_API_KEY: undefined,
      OPENAI_MODEL: "gpt-4o",
      ANTHROPIC_API_KEY: undefined,
      ANTHROPIC_MODEL: "claude-sonnet-4-20250514",
      APP_NAME: "Clarissa",
      APP_URL: undefined,
      MAX_ITERATIONS: 10,
      DEBUG: false,
      PROVIDER: undefined,
      LMSTUDIO_MODEL: undefined,
      LOCAL_MODEL_PATH: undefined,
    };
  }

  // Load config file and preferences
  const fileConfig = loadConfigFile();
  loadedPreferences = loadPreferencesFile();

  // Priority order: env vars > config file > saved preferences > defaults
  const mergedEnv = {
    ...process.env,
    // API keys: env vars are backup, config file is primary
    OPENROUTER_API_KEY: process.env.OPENROUTER_API_KEY || fileConfig?.openrouterApiKey,
    OPENAI_API_KEY: process.env.OPENAI_API_KEY || fileConfig?.openaiApiKey,
    ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY || fileConfig?.anthropicApiKey,
    // Model/provider from preferences (runtime choices persist)
    OPENROUTER_MODEL: process.env.OPENROUTER_MODEL || loadedPreferences.lastModel,
    MAX_ITERATIONS: process.env.MAX_ITERATIONS || fileConfig?.maxIterations?.toString(),
    DEBUG: process.env.DEBUG || (fileConfig?.debug ? "true" : undefined),
    // Provider from preferences (runtime choice persists)
    PROVIDER: process.env.LLM_PROVIDER || loadedPreferences.lastProvider,
    LMSTUDIO_MODEL: process.env.LMSTUDIO_MODEL || fileConfig?.lmstudioModel,
    LOCAL_MODEL_PATH: process.env.LOCAL_MODEL_PATH || fileConfig?.localModelPath,
  };

  const result = envSchema.safeParse(mergedEnv);

  if (!result.success) {
    // Only show setup instructions if validation truly fails
    // With optional API key, this should rarely happen
    console.error("Config validation error:", result.error.format());
    showSetupInstructions();
  }

  return result.data;
}

export const config = loadConfig();

// Popular models available on OpenRouter
export const AVAILABLE_MODELS = [
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

/**
 * Agent configuration class with mutable state
 */
class AgentConfig {
  model: string;
  readonly maxIterations: number;
  readonly appName: string;
  readonly debug: boolean;
  autoApprove: boolean;

  constructor() {
    this.model = config.OPENROUTER_MODEL;
    this.maxIterations = config.MAX_ITERATIONS;
    this.appName = config.APP_NAME;
    this.debug = config.DEBUG;
    this.autoApprove = false;
  }

  /**
   * Change the current model
   */
  setModel(model: string): void {
    this.model = model;
  }

  /**
   * Toggle auto-approve mode
   */
  toggleAutoApprove(): boolean {
    this.autoApprove = !this.autoApprove;
    return this.autoApprove;
  }
}

export const agentConfig = new AgentConfig();

