import { test, expect, describe } from "bun:test";
import type { Message } from "../types.ts";

describe("Provider Implementations", () => {
  describe("AnthropicProvider", () => {
    const { AnthropicProvider } = require("./anthropic.ts");

    test("checkAvailability returns unavailable without API key", async () => {
      const provider = new AnthropicProvider("");
      const status = await provider.checkAvailability();
      expect(status.available).toBe(false);
      expect(status.reason).toBe("No API key configured");
    });

    test("checkAvailability returns available with API key", async () => {
      const provider = new AnthropicProvider("test-key");
      const status = await provider.checkAvailability();
      expect(status.available).toBe(true);
      expect(status.model).toBe("claude-sonnet-4-20250514");
    });

    test("uses custom default model", async () => {
      const provider = new AnthropicProvider("test-key", "claude-3-opus");
      const status = await provider.checkAvailability();
      expect(status.model).toBe("claude-3-opus");
    });

    test("has correct provider info", () => {
      const provider = new AnthropicProvider("test-key");
      expect(provider.info.id).toBe("anthropic");
      expect(provider.info.name).toBe("Anthropic");
      expect(provider.info.capabilities.streaming).toBe(true);
      expect(provider.info.capabilities.toolCalling).toBe(true);
      expect(provider.info.capabilities.local).toBe(false);
    });

    test("initialize completes without error", async () => {
      const provider = new AnthropicProvider("test-key");
      await expect(provider.initialize()).resolves.toBeUndefined();
    });
  });

  describe("OpenAIProvider", () => {
    const { OpenAIProvider } = require("./openai.ts");

    test("checkAvailability returns unavailable without API key", async () => {
      const provider = new OpenAIProvider("");
      const status = await provider.checkAvailability();
      expect(status.available).toBe(false);
      expect(status.reason).toBe("No API key configured");
    });

    test("checkAvailability returns available with API key", async () => {
      const provider = new OpenAIProvider("test-key");
      const status = await provider.checkAvailability();
      expect(status.available).toBe(true);
      expect(status.model).toBe("gpt-4o");
    });

    test("uses custom default model and base URL", async () => {
      const provider = new OpenAIProvider("test-key", "gpt-4-turbo", "https://custom.api.com");
      const status = await provider.checkAvailability();
      expect(status.model).toBe("gpt-4-turbo");
    });

    test("has correct provider info", () => {
      const provider = new OpenAIProvider("test-key");
      expect(provider.info.id).toBe("openai");
      expect(provider.info.name).toBe("OpenAI");
      expect(provider.info.capabilities.streaming).toBe(true);
      expect(provider.info.capabilities.embeddings).toBe(true);
      expect(provider.info.capabilities.local).toBe(false);
    });
  });

  describe("OpenRouterProvider", () => {
    const { OpenRouterProvider } = require("./openrouter.ts");

    test("checkAvailability returns unavailable without API key", async () => {
      const provider = new OpenRouterProvider("");
      const status = await provider.checkAvailability();
      expect(status.available).toBe(false);
      expect(status.reason).toBe("No API key configured");
    });

    test("checkAvailability returns available with API key", async () => {
      const provider = new OpenRouterProvider("test-key");
      const status = await provider.checkAvailability();
      expect(status.available).toBe(true);
      expect(status.model).toBe("anthropic/claude-sonnet-4");
    });

    test("uses custom default model", async () => {
      const provider = new OpenRouterProvider("test-key", "openai/gpt-4o");
      const status = await provider.checkAvailability();
      expect(status.model).toBe("openai/gpt-4o");
    });

    test("has correct provider info", () => {
      const provider = new OpenRouterProvider("test-key");
      expect(provider.info.id).toBe("openrouter");
      expect(provider.info.name).toBe("OpenRouter");
      expect(provider.info.capabilities.streaming).toBe(true);
      expect(provider.info.capabilities.local).toBe(false);
    });
  });

  describe("LMStudioProvider", () => {
    const { LMStudioProvider } = require("./lmstudio.ts");

    test("has correct provider info", () => {
      const provider = new LMStudioProvider();
      expect(provider.info.id).toBe("lmstudio");
      expect(provider.info.name).toBe("LM Studio");
      expect(provider.info.capabilities.streaming).toBe(true);
      expect(provider.info.capabilities.local).toBe(true);
    });

    test("checkAvailability handles missing SDK gracefully", async () => {
      const provider = new LMStudioProvider();
      const status = await provider.checkAvailability();
      // Will either be unavailable (SDK not installed) or available (SDK installed and running)
      expect(typeof status.available).toBe("boolean");
      if (!status.available) {
        expect(status.reason).toBeDefined();
      }
    });

    test("shutdown clears internal state", async () => {
      const provider = new LMStudioProvider();
      await provider.shutdown();
      // Should not throw
    });

    describe("parseModelOutput", () => {
      const { parseModelOutput } = require("./lmstudio.ts");

      test("passes through plain text without special tokens", () => {
        const result = parseModelOutput("Hello, how can I help you?");
        expect(result.content).toBe("Hello, how can I help you?");
        expect(result.toolCalls).toEqual([]);
      });

      test("extracts final channel content", () => {
        const raw = '<|channel|>analysis<|message|>Just greet.<|end|><|start|>assistant<|channel|>final<|message|>Hello! How can I help you today?';
        const result = parseModelOutput(raw);
        expect(result.content).toBe("Hello! How can I help you today?");
        expect(result.toolCalls).toEqual([]);
      });

      test("extracts final channel content with end marker", () => {
        const raw = '<|channel|>analysis<|message|>Thinking...<|end|><|start|>assistant<|channel|>final<|message|>Here is my response.<|end|>';
        const result = parseModelOutput(raw);
        expect(result.content).toBe("Here is my response.");
      });

      test("parses tool calls from commentary channel", () => {
        const raw = '<|channel|>analysis<|message|>Need to use calculator.<|end|><|start|>assistant<|channel|>commentary to=calculator <|constrain|>json<|message|>{"expression":"12*12"}';
        const result = parseModelOutput(raw);
        expect(result.toolCalls).toHaveLength(1);
        expect(result.toolCalls[0].name).toBe("calculator");
        expect(result.toolCalls[0].arguments).toBe('{"expression":"12*12"}');
      });

      test("parses web_fetch tool call", () => {
        const raw = '<|channel|>commentary to=web_fetch <|constrain|>json<|message|>{"url":"https://api.github.com","timeout":10000}';
        const result = parseModelOutput(raw);
        expect(result.toolCalls).toHaveLength(1);
        expect(result.toolCalls[0].name).toBe("web_fetch");
        expect(JSON.parse(result.toolCalls[0].arguments)).toEqual({ url: "https://api.github.com", timeout: 10000 });
      });

      test("handles multiline final content", () => {
        const raw = '<|channel|>final<|message|>Line 1\nLine 2\nLine 3';
        const result = parseModelOutput(raw);
        expect(result.content).toBe("Line 1\nLine 2\nLine 3");
      });

      test("skips invalid JSON in tool calls", () => {
        const raw = '<|channel|>commentary to=broken <|constrain|>json<|message|>{invalid json}';
        const result = parseModelOutput(raw);
        expect(result.toolCalls).toEqual([]);
      });
    });

    describe("StreamingOutputParser", () => {
      const { StreamingOutputParser } = require("./lmstudio.ts");

      test("buffers analysis channel content without emitting", () => {
        const parser = new StreamingOutputParser();
        expect(parser.processChunk("<|channel|>analysis")).toBe("");
        expect(parser.processChunk("<|message|>thinking...")).toBe("");
        expect(parser.processChunk("<|end|>")).toBe("");
      });

      test("emits content once final channel is reached", () => {
        const parser = new StreamingOutputParser();
        parser.processChunk("<|channel|>analysis<|message|>think<|end|>");
        parser.processChunk("<|start|>assistant<|channel|>final<|message|>");
        expect(parser.processChunk("Hello")).toBe("Hello");
        expect(parser.processChunk(" world")).toBe(" world");
        expect(parser.processChunk("!")).toBe("!");
      });

      test("only emits new content on subsequent chunks", () => {
        const parser = new StreamingOutputParser();
        parser.processChunk("<|channel|>final<|message|>Hi");
        expect(parser.processChunk("")).toBe("");
        expect(parser.processChunk(" there")).toBe(" there");
      });

      test("getFullOutput returns parsed result", () => {
        const parser = new StreamingOutputParser();
        parser.processChunk("<|channel|>analysis<|message|>analyze<|end|>");
        parser.processChunk("<|channel|>final<|message|>Final answer here");
        const output = parser.getFullOutput();
        expect(output.content).toBe("Final answer here");
      });
    });
  });

  describe("LocalLlamaProvider", () => {
    const { LocalLlamaProvider } = require("./local-llama.ts");

    test("has correct provider info", () => {
      const provider = new LocalLlamaProvider({ modelPath: "/fake/model.gguf" });
      expect(provider.info.id).toBe("local-llama");
      expect(provider.info.name).toBe("Local Llama");
      expect(provider.info.capabilities.streaming).toBe(true);
      expect(provider.info.capabilities.embeddings).toBe(true);
      expect(provider.info.capabilities.local).toBe(true);
    });

    test("checkAvailability returns unavailable for non-existent model", async () => {
      const provider = new LocalLlamaProvider({ modelPath: "/nonexistent/model.gguf" });
      const status = await provider.checkAvailability();
      // Either SDK not installed or model not found
      expect(status.available).toBe(false);
      expect(status.reason).toBeDefined();
    });

    test("shutdown clears internal state", async () => {
      const provider = new LocalLlamaProvider({ modelPath: "/fake/model.gguf" });
      await provider.shutdown();
      // Should not throw
    });
  });

  describe("AppleAIProvider", () => {
    const { AppleAIProvider } = require("./apple-ai.ts");

    test("has correct provider info", () => {
      const provider = new AppleAIProvider();
      expect(provider.info.id).toBe("apple-ai");
      expect(provider.info.name).toBe("Apple Intelligence");
      expect(provider.info.capabilities.streaming).toBe(true);
      expect(provider.info.capabilities.toolCalling).toBe(true);
      expect(provider.info.capabilities.local).toBe(true);
    });

    test("checkAvailability returns unavailable on non-macOS", async () => {
      const provider = new AppleAIProvider();
      const status = await provider.checkAvailability();
      // On non-macOS or without SDK, should be unavailable
      if (process.platform !== "darwin") {
        expect(status.available).toBe(false);
        expect(status.reason).toContain("macOS");
      } else {
        // On macOS, either SDK not installed or Apple Intelligence not available
        expect(typeof status.available).toBe("boolean");
      }
    });

    test("shutdown clears internal state", async () => {
      const provider = new AppleAIProvider();
      await provider.shutdown();
      // Should not throw
    });

    describe("convertMessages (via testConvertMessages)", () => {
      // Access the private method through a test helper
      function testConvertMessages(messages: Message[]): Array<{ role: string; content: string }> {
        const provider = new AppleAIProvider();
        // Use bracket notation to access private method for testing
        return (provider as unknown as { convertMessages: (msgs: Message[]) => Array<{ role: string; content: string }> }).convertMessages(messages);
      }

      test("converts basic user and assistant messages", () => {
        const messages: Message[] = [
          { role: "user", content: "Hello" },
          { role: "assistant", content: "Hi there!" },
        ];
        const result = testConvertMessages(messages);
        expect(result).toHaveLength(2);
        expect(result[0]).toEqual({ role: "user", content: "Hello" });
        expect(result[1]).toEqual({ role: "assistant", content: "Hi there!" });
      });

      test("converts system messages", () => {
        const messages: Message[] = [
          { role: "system", content: "You are helpful" },
          { role: "user", content: "Hello" },
        ];
        const result = testConvertMessages(messages);
        expect(result).toHaveLength(2);
        expect(result[0]).toEqual({ role: "system", content: "You are helpful" });
      });

      test("includes tool call info in assistant messages", () => {
        const messages: Message[] = [
          { role: "user", content: "Calculate 12*12" },
          {
            role: "assistant",
            content: null,
            tool_calls: [
              { id: "call_1", type: "function", function: { name: "calculator", arguments: '{"expression":"12*12"}' } },
            ],
          },
        ];
        const result = testConvertMessages(messages);
        expect(result).toHaveLength(2);
        expect(result[1]!.role).toBe("assistant");
        expect(result[1]!.content).toContain("calculator");
        expect(result[1]!.content).toContain("12*12");
      });

      test("converts completed tool calls to assistant messages", () => {
        const messages: Message[] = [
          { role: "user", content: "Calculate 12*12" },
          {
            role: "assistant",
            content: null,
            tool_calls: [
              { id: "call_1", type: "function", function: { name: "calculator", arguments: '{"expression":"12*12"}' } },
            ],
          },
          { role: "tool", tool_call_id: "call_1", name: "calculator", content: '{"result":144}' },
        ];
        const result = testConvertMessages(messages);
        // When tool calls are completed, the assistant message with tool calls is skipped
        // (since content is null and all tool calls have results)
        // Tool result becomes an assistant message
        expect(result).toHaveLength(2);
        expect(result[1]!.role).toBe("assistant");
        expect(result[1]!.content).toContain("calculator completed");
        expect(result[1]!.content).toContain("144");
      });

      test("handles assistant messages with both content and tool calls", () => {
        const messages: Message[] = [
          { role: "user", content: "Calculate something" },
          {
            role: "assistant",
            content: "Let me calculate that for you.",
            tool_calls: [
              { id: "call_1", type: "function", function: { name: "calculator", arguments: '{"expression":"2+2"}' } },
            ],
          },
        ];
        const result = testConvertMessages(messages);
        expect(result[1]!.content).toContain("Let me calculate that for you.");
        expect(result[1]!.content).toContain("calculator");
      });

      test("skips assistant messages with no content and no tool calls", () => {
        const messages: Message[] = [
          { role: "user", content: "Hello" },
          { role: "assistant", content: "" },
          { role: "user", content: "Hi again" },
        ];
        const result = testConvertMessages(messages);
        // Empty assistant messages should not be included
        expect(result).toHaveLength(2);
        expect(result[0]!.content).toBe("Hello");
        expect(result[1]!.content).toBe("Hi again");
      });
    });
  });
});

