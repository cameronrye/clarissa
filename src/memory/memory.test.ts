import { test, expect, describe, beforeEach, afterEach } from "bun:test";
import { mkdir } from "fs/promises";
import { join } from "path";
import { homedir } from "os";
import { memoryManager } from "./index.ts";

const MEMORY_FILE = join(homedir(), ".clarissa", "memories.json");

describe("Memory Manager", () => {
  let originalContent: string | null = null;

  beforeEach(async () => {
    // Backup existing memories if any
    try {
      const file = Bun.file(MEMORY_FILE);
      if (await file.exists()) {
        originalContent = await file.text();
      }
    } catch {
      originalContent = null;
    }
    // Clear memories for tests
    await memoryManager.clear();
  });

  afterEach(async () => {
    // Restore original content
    if (originalContent !== null) {
      await mkdir(join(homedir(), ".clarissa"), { recursive: true });
      await Bun.write(MEMORY_FILE, originalContent);
      // Reset loaded state so it reloads from restored file
      (memoryManager as unknown as { loaded: boolean }).loaded = false;
    }
  });

  test("add creates a memory with id and timestamp", async () => {
    const memory = await memoryManager.add("Test memory content");

    expect(memory.id).toMatch(/^mem_\d+_[a-z0-9]+$/);
    expect(memory.content).toBe("Test memory content");
    expect(memory.createdAt).toBeDefined();
  });

  test("list returns all memories", async () => {
    await memoryManager.add("First memory");
    await memoryManager.add("Second memory");

    const memories = await memoryManager.list();

    expect(memories).toHaveLength(2);
    expect(memories[0]!.content).toBe("First memory");
    expect(memories[1]!.content).toBe("Second memory");
  });

  test("forget removes memory by index (1-based)", async () => {
    await memoryManager.add("First");
    await memoryManager.add("Second");
    await memoryManager.add("Third");

    const forgotten = await memoryManager.forget("2");

    expect(forgotten).toBe(true);
    const memories = await memoryManager.list();
    expect(memories).toHaveLength(2);
    expect(memories[0]!.content).toBe("First");
    expect(memories[1]!.content).toBe("Third");
  });

  test("forget removes memory by ID", async () => {
    const memory = await memoryManager.add("To be forgotten");

    const forgotten = await memoryManager.forget(memory.id);

    expect(forgotten).toBe(true);
    const memories = await memoryManager.list();
    expect(memories).toHaveLength(0);
  });

  test("forget returns false for non-existent memory", async () => {
    const forgotten = await memoryManager.forget("nonexistent");

    expect(forgotten).toBe(false);
  });

  test("clear removes all memories", async () => {
    await memoryManager.add("One");
    await memoryManager.add("Two");
    await memoryManager.clear();

    const memories = await memoryManager.list();
    expect(memories).toHaveLength(0);
  });

  test("getForPrompt returns null when no memories", async () => {
    const prompt = await memoryManager.getForPrompt();

    expect(prompt).toBeNull();
  });

  test("getForPrompt returns formatted string with memories", async () => {
    await memoryManager.add("Always use tabs");
    await memoryManager.add("Prefer functional style");

    const prompt = await memoryManager.getForPrompt();

    expect(prompt).toContain("## Remembered Context");
    expect(prompt).toContain("- Always use tabs");
    expect(prompt).toContain("- Prefer functional style");
  });

  test("memories persist to disk", async () => {
    await memoryManager.add("Persistent memory");

    // Check file exists and contains the memory
    const file = Bun.file(MEMORY_FILE);
    expect(await file.exists()).toBe(true);

    const content = await file.json();
    expect(content).toHaveLength(1);
    expect(content[0].content).toBe("Persistent memory");
  });
});

