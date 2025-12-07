/**
 * Token usage and cost tracking for Clarissa
 */

export interface UsageData {
  promptTokens: number;
  completionTokens: number;
  totalTokens: number;
  estimatedCost: number;
}

export interface SessionUsage {
  requests: number;
  promptTokens: number;
  completionTokens: number;
  totalTokens: number;
  estimatedCost: number;
}

// Approximate pricing per 1M tokens (as of Dec 2025)
// These are estimates - actual costs depend on the model
const MODEL_PRICING: Record<string, { input: number; output: number }> = {
  "anthropic/claude-sonnet-4": { input: 3.0, output: 15.0 },
  "anthropic/claude-opus-4": { input: 15.0, output: 75.0 },
  "anthropic/claude-3.5-sonnet": { input: 3.0, output: 15.0 },
  "openai/gpt-4o": { input: 2.5, output: 10.0 },
  "openai/gpt-4o-mini": { input: 0.15, output: 0.6 },
  "google/gemini-2.0-flash": { input: 0.1, output: 0.4 },
  default: { input: 1.0, output: 3.0 },
};

/**
 * Usage tracker for the current session
 */
class UsageTracker {
  private usage: SessionUsage = {
    requests: 0,
    promptTokens: 0,
    completionTokens: 0,
    totalTokens: 0,
    estimatedCost: 0,
  };

  private currentModel: string = "default";

  /**
   * Set the current model for cost calculation
   */
  setModel(model: string): void {
    this.currentModel = model;
  }

  /**
   * Add usage from a request
   */
  addUsage(promptTokens: number, completionTokens: number): UsageData {
    this.usage.requests++;
    this.usage.promptTokens += promptTokens;
    this.usage.completionTokens += completionTokens;
    this.usage.totalTokens += promptTokens + completionTokens;

    const pricing = MODEL_PRICING[this.currentModel] ?? MODEL_PRICING.default!;
    const cost =
      (promptTokens / 1_000_000) * pricing!.input +
      (completionTokens / 1_000_000) * pricing!.output;

    this.usage.estimatedCost += cost;

    return {
      promptTokens,
      completionTokens,
      totalTokens: promptTokens + completionTokens,
      estimatedCost: cost,
    };
  }

  /**
   * Estimate tokens from text (rough approximation)
   * ~4 characters per token for English text
   */
  estimateTokens(text: string): number {
    return Math.ceil(text.length / 4);
  }

  /**
   * Get session usage summary
   */
  getSessionUsage(): SessionUsage {
    return { ...this.usage };
  }

  /**
   * Format usage for display
   */
  formatUsage(): string {
    const { requests, totalTokens, estimatedCost } = this.usage;
    return `${requests} requests | ${totalTokens.toLocaleString()} tokens | ~$${estimatedCost.toFixed(4)}`;
  }

  /**
   * Reset session usage
   */
  reset(): void {
    this.usage = {
      requests: 0,
      promptTokens: 0,
      completionTokens: 0,
      totalTokens: 0,
      estimatedCost: 0,
    };
  }
}

export const usageTracker = new UsageTracker();

