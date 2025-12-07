import { test, expect, describe, beforeEach, afterEach } from "bun:test";
import { rm, mkdir } from "fs/promises";
import { join } from "path";
import { homedir } from "os";
import { sessionManager } from "./index.ts";
import type { Message } from "../llm/types.ts";

const TEST_SESSION_DIR = join(homedir(), ".clarissa", "sessions");

describe("Session Load and List", () => {
  // Track created session IDs for cleanup
  let createdSessionIds: string[] = [];

  beforeEach(async () => {
    await mkdir(TEST_SESSION_DIR, { recursive: true });
    createdSessionIds = [];
  });

  afterEach(async () => {
    // Clean up created sessions
    for (const id of createdSessionIds) {
      try {
        const path = join(TEST_SESSION_DIR, `${id}.json`);
        await rm(path, { force: true });
      } catch {
        // Ignore cleanup errors
      }
    }
  });

  describe("load", () => {
    test("loads existing session", async () => {
      const created = await sessionManager.create("Loadable Session");
      createdSessionIds.push(created.id);
      const loaded = await sessionManager.load(created.id);
      expect(loaded).not.toBeNull();
      expect(loaded!.name).toBe("Loadable Session");
    });

    test("returns null for non-existent session", async () => {
      const loaded = await sessionManager.load("nonexistent_session");
      expect(loaded).toBeNull();
    });

    test("preserves messages", async () => {
      const created = await sessionManager.create();
      createdSessionIds.push(created.id);
      const messages: Message[] = [
        { role: "user", content: "Hello" },
        { role: "assistant", content: "Hi there!" },
      ];
      sessionManager.updateMessages(messages);
      await sessionManager.save();
      const loaded = await sessionManager.load(created.id);
      expect(loaded!.messages).toHaveLength(2);
      expect(loaded!.messages[0]!.content).toBe("Hello");
    });
  });

  describe("updateMessages", () => {
    test("updates messages in current session", async () => {
      const session = await sessionManager.create();
      createdSessionIds.push(session.id);
      const messages: Message[] = [{ role: "user", content: "Test" }];
      sessionManager.updateMessages(messages);
      expect(sessionManager.getMessages()).toHaveLength(1);
    });
  });
});

