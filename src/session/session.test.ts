import { test, expect, describe, beforeEach, afterEach } from "bun:test";
import { rm, mkdir } from "fs/promises";
import { join } from "path";
import { homedir } from "os";
import { sessionManager } from "./index.ts";

const TEST_SESSION_DIR = join(homedir(), ".clarissa", "sessions");

describe("Session Management", () => {
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

  describe("create", () => {
    test("creates new session with generated ID", async () => {
      const session = await sessionManager.create();
      createdSessionIds.push(session.id);
      expect(session.id).toMatch(/^session_\d+_[a-z0-9]+$/);
      expect(session.messages).toEqual([]);
    });

    test("creates session with custom name", async () => {
      const session = await sessionManager.create("My Custom Session");
      createdSessionIds.push(session.id);
      expect(session.name).toBe("My Custom Session");
    });

    test("creates session with default name", async () => {
      const session = await sessionManager.create();
      createdSessionIds.push(session.id);
      expect(session.name).toContain("Session");
    });

    test("sets createdAt and updatedAt timestamps", async () => {
      const session = await sessionManager.create();
      createdSessionIds.push(session.id);
      expect(session.createdAt).toBeDefined();
      expect(session.updatedAt).toBeDefined();
      expect(new Date(session.createdAt).getTime()).toBeLessThanOrEqual(Date.now());
    });
  });

  describe("save", () => {
    test("persists session to disk", async () => {
      const session = await sessionManager.create("Test Session");
      createdSessionIds.push(session.id);
      await sessionManager.save();
      const file = Bun.file(join(TEST_SESSION_DIR, `${session.id}.json`));
      expect(await file.exists()).toBe(true);
    });

    test("updates updatedAt on save", async () => {
      const session = await sessionManager.create();
      createdSessionIds.push(session.id);
      const originalUpdatedAt = session.updatedAt;
      await new Promise(r => setTimeout(r, 10));
      await sessionManager.save();
      expect(sessionManager.getCurrent()!.updatedAt).not.toBe(originalUpdatedAt);
    });
  });
});

