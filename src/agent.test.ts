import { describe, test, expect } from "bun:test";
import { Agent } from "./agent.ts";
import type { Message } from "./llm/types.ts";

describe("Agent", () => {
  describe("constructor and callbacks", () => {
    test("creates agent with default callbacks", () => {
      const agent = new Agent();
      expect(agent).toBeInstanceOf(Agent);
    });

    test("creates agent with custom callbacks", () => {
      const callbacks = {
        onThinking: () => {},
        onResponse: () => {},
      };
      const agent = new Agent(callbacks);
      expect(agent).toBeInstanceOf(Agent);
    });
  });

  describe("reset", () => {
    test("clears messages but keeps system prompt", () => {
      const agent = new Agent();
      // Manually load some messages to simulate a conversation
      const messages: Message[] = [
        { role: "system", content: "You are a helpful assistant" },
        { role: "user", content: "Hello" },
        { role: "assistant", content: "Hi there!" },
      ];
      agent.loadMessages(messages);

      // History should have system + user + assistant
      const beforeReset = agent.getHistory();
      expect(beforeReset.length).toBeGreaterThanOrEqual(2);

      agent.reset();

      const afterReset = agent.getHistory();
      // After reset, should have at most the system message
      expect(afterReset.length).toBeLessThanOrEqual(1);
      if (afterReset.length === 1) {
        expect(afterReset[0]!.role).toBe("system");
      }
    });

    test("handles reset with no messages", () => {
      const agent = new Agent();
      agent.reset();
      expect(agent.getHistory()).toEqual([]);
    });
  });

  describe("loadMessages", () => {
    test("loads messages from a saved session", () => {
      const agent = new Agent();
      const messages: Message[] = [
        { role: "user", content: "Hello" },
        { role: "assistant", content: "Hi!" },
        { role: "user", content: "How are you?" },
        { role: "assistant", content: "Good!" },
      ];
      agent.loadMessages(messages);

      const history = agent.getHistory();
      expect(history.length).toBe(4);
      expect(history[0]!.role).toBe("user");
      expect(history[0]!.content).toBe("Hello");
    });

    test("filters out system messages from loaded session", () => {
      const agent = new Agent();
      const messages: Message[] = [
        { role: "system", content: "Old system prompt" },
        { role: "user", content: "Hello" },
        { role: "assistant", content: "Hi!" },
      ];
      agent.loadMessages(messages);

      const history = agent.getHistory();
      // System message from session should be excluded
      const systemMessages = history.filter((m) => m.role === "system");
      const userMessages = history.filter((m) => m.role === "user");

      expect(systemMessages.length).toBe(0);
      expect(userMessages.length).toBe(1);
    });
  });

  describe("getMessagesForSave", () => {
    test("excludes system messages", () => {
      const agent = new Agent();
      const messages: Message[] = [
        { role: "user", content: "Hello" },
        { role: "assistant", content: "Hi!" },
      ];
      agent.loadMessages(messages);

      const forSave = agent.getMessagesForSave();
      expect(forSave.every((m) => m.role !== "system")).toBe(true);
      expect(forSave.length).toBe(2);
    });
  });

  describe("getHistory", () => {
    test("returns a copy of messages", () => {
      const agent = new Agent();
      const messages: Message[] = [
        { role: "user", content: "Hello" },
      ];
      agent.loadMessages(messages);

      const history1 = agent.getHistory();
      const history2 = agent.getHistory();

      // Should be different array instances
      expect(history1).not.toBe(history2);
      // But same content
      expect(history1).toEqual(history2);
    });
  });

  describe("abort", () => {
    test("abort is safe to call when no run is in progress", () => {
      const agent = new Agent();
      // Should not throw
      expect(() => agent.abort()).not.toThrow();
    });

    test("abort can be called multiple times safely", () => {
      const agent = new Agent();
      expect(() => {
        agent.abort();
        agent.abort();
        agent.abort();
      }).not.toThrow();
    });
  });
});
