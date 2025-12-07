import { test, expect, describe, beforeEach } from "bun:test";

// Test a fresh instance of UsageTracker
class TestableUsageTracker {
  private usage = {
    requests: 0,
    promptTokens: 0,
    completionTokens: 0,
    totalTokens: 0,
    estimatedCost: 0,
  };

  private currentModel: string = "default";

  private MODEL_PRICING: Record<string, { input: number; output: number }> = {
    "anthropic/claude-sonnet-4": { input: 3.0, output: 15.0 },
    "anthropic/claude-opus-4": { input: 15.0, output: 75.0 },
    "anthropic/claude-3.5-sonnet": { input: 3.0, output: 15.0 },
    "openai/gpt-4o": { input: 2.5, output: 10.0 },
    "openai/gpt-4o-mini": { input: 0.15, output: 0.6 },
    "google/gemini-2.0-flash": { input: 0.1, output: 0.4 },
    default: { input: 1.0, output: 3.0 },
  };

  setModel(model: string): void {
    this.currentModel = model;
  }

  addUsage(promptTokens: number, completionTokens: number) {
    this.usage.requests++;
    this.usage.promptTokens += promptTokens;
    this.usage.completionTokens += completionTokens;
    this.usage.totalTokens += promptTokens + completionTokens;

    const pricing = this.MODEL_PRICING[this.currentModel] ?? this.MODEL_PRICING.default!;
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

  estimateTokens(text: string): number {
    return Math.ceil(text.length / 4);
  }

  getSessionUsage() {
    return { ...this.usage };
  }

  formatUsage(): string {
    const { requests, totalTokens, estimatedCost } = this.usage;
    return `${requests} requests | ${totalTokens.toLocaleString()} tokens | ~$${estimatedCost.toFixed(4)}`;
  }

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

describe("Usage Tracking", () => {
  let tracker: TestableUsageTracker;

  beforeEach(() => {
    tracker = new TestableUsageTracker();
  });

  describe("estimateTokens", () => {
    test("estimates ~4 chars per token", () => {
      expect(tracker.estimateTokens("hello")).toBe(2); // 5 chars / 4 = 1.25, ceil = 2
      expect(tracker.estimateTokens("hello world")).toBe(3); // 11 chars / 4 = 2.75, ceil = 3
    });

    test("handles empty string", () => {
      expect(tracker.estimateTokens("")).toBe(0);
    });

    test("handles long text", () => {
      const longText = "a".repeat(1000);
      expect(tracker.estimateTokens(longText)).toBe(250);
    });
  });

  describe("addUsage", () => {
    test("tracks prompt and completion tokens", () => {
      tracker.addUsage(100, 50);
      const usage = tracker.getSessionUsage();
      expect(usage.promptTokens).toBe(100);
      expect(usage.completionTokens).toBe(50);
      expect(usage.totalTokens).toBe(150);
    });

    test("increments request count", () => {
      tracker.addUsage(100, 50);
      tracker.addUsage(200, 100);
      const usage = tracker.getSessionUsage();
      expect(usage.requests).toBe(2);
    });

    test("accumulates tokens across requests", () => {
      tracker.addUsage(100, 50);
      tracker.addUsage(200, 100);
      const usage = tracker.getSessionUsage();
      expect(usage.promptTokens).toBe(300);
      expect(usage.completionTokens).toBe(150);
    });

    test("calculates cost for default model", () => {
      // Default: $1/1M input, $3/1M output
      const result = tracker.addUsage(1_000_000, 1_000_000);
      expect(result.estimatedCost).toBe(4.0); // $1 + $3
    });

    test("calculates cost for claude-sonnet-4", () => {
      tracker.setModel("anthropic/claude-sonnet-4");
      // Claude Sonnet 4: $3/1M input, $15/1M output
      const result = tracker.addUsage(1_000_000, 1_000_000);
      expect(result.estimatedCost).toBe(18.0); // $3 + $15
    });

    test("calculates cost for gpt-4o-mini", () => {
      tracker.setModel("openai/gpt-4o-mini");
      // GPT-4o-mini: $0.15/1M input, $0.6/1M output
      const result = tracker.addUsage(1_000_000, 1_000_000);
      expect(result.estimatedCost).toBeCloseTo(0.75, 5); // $0.15 + $0.6
    });
  });

  describe("formatUsage", () => {
    test("formats usage summary", () => {
      tracker.addUsage(1000, 500);
      const formatted = tracker.formatUsage();
      expect(formatted).toContain("1 requests");
      expect(formatted).toContain("1,500 tokens");
      expect(formatted).toContain("~$");
    });
  });

  describe("reset", () => {
    test("resets all counters", () => {
      tracker.addUsage(1000, 500);
      tracker.reset();
      const usage = tracker.getSessionUsage();
      expect(usage.requests).toBe(0);
      expect(usage.promptTokens).toBe(0);
      expect(usage.completionTokens).toBe(0);
      expect(usage.totalTokens).toBe(0);
      expect(usage.estimatedCost).toBe(0);
    });
  });
});

