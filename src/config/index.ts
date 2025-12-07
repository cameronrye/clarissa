import { z } from "zod";

/**
 * Environment configuration schema with Zod validation
 */
const envSchema = z.object({
  OPENROUTER_API_KEY: z.string().min(1, "OPENROUTER_API_KEY is required"),
  OPENROUTER_MODEL: z
    .string()
    .default("anthropic/claude-sonnet-4"),
  APP_NAME: z.string().default("Clarissa"),
  APP_URL: z.string().url().optional(),
  MAX_ITERATIONS: z.coerce.number().int().positive().default(10),
  DEBUG: z
    .string()
    .optional()
    .default("false")
    .transform((val) => val === "true" || val === "1"),
});

export type EnvConfig = z.infer<typeof envSchema>;

/**
 * Validate and parse environment variables
 */
function loadConfig(): EnvConfig {
  const result = envSchema.safeParse(process.env);

  if (!result.success) {
    console.error("❌ Invalid environment configuration:");
    const issues = result.error.issues;
    for (const issue of issues) {
      const path = Array.isArray(issue.path) ? issue.path.join(".") : String(issue.path);
      console.error(`   - ${path}: ${issue.message}`);
    }
    console.error("\nPlease set the required environment variables.");
    console.error("Example: export OPENROUTER_API_KEY=your_api_key_here");
    process.exit(1);
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

