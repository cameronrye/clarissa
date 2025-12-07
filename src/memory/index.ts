import { join } from "path";
import { homedir } from "os";
import { mkdir } from "fs/promises";

const MEMORY_FILE = join(homedir(), ".clarissa", "memories.json");

export interface Memory {
  id: string;
  content: string;
  createdAt: string;
}

/**
 * Memory manager for persisting knowledge across sessions
 */
class MemoryManager {
  private memories: Memory[] = [];
  private loaded = false;
  private version = 0; // Incremented on changes, used for cache invalidation

  /**
   * Ensure memory directory exists
   */
  private async ensureDir(): Promise<void> {
    await mkdir(join(homedir(), ".clarissa"), { recursive: true });
  }

  /**
   * Generate a unique memory ID
   */
  private generateId(): string {
    return `mem_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`;
  }

  /**
   * Load memories from disk
   */
  async load(): Promise<void> {
    if (this.loaded) return;

    try {
      await this.ensureDir();
      const file = Bun.file(MEMORY_FILE);

      if (await file.exists()) {
        const content = await file.json();
        this.memories = content as Memory[];
      }
      this.loaded = true;
    } catch {
      this.memories = [];
      this.loaded = true;
    }
  }

  /**
   * Save memories to disk
   */
  async save(): Promise<void> {
    await this.ensureDir();
    await Bun.write(MEMORY_FILE, JSON.stringify(this.memories, null, 2));
  }

  /**
   * Add a new memory
   */
  async add(content: string): Promise<Memory> {
    await this.load();

    const memory: Memory = {
      id: this.generateId(),
      content: content.trim(),
      createdAt: new Date().toISOString(),
    };

    this.memories.push(memory);
    this.version++;
    await this.save();

    return memory;
  }

  /**
   * Get all memories
   */
  async list(): Promise<Memory[]> {
    await this.load();
    return [...this.memories];
  }

  /**
   * Delete a memory by ID or index
   */
  async forget(idOrIndex: string): Promise<boolean> {
    await this.load();

    // Try as index first (1-based for user friendliness)
    const index = parseInt(idOrIndex, 10);
    if (!isNaN(index) && index >= 1 && index <= this.memories.length) {
      this.memories.splice(index - 1, 1);
      this.version++;
      await this.save();
      return true;
    }

    // Try as ID
    const memoryIndex = this.memories.findIndex((m) => m.id === idOrIndex);
    if (memoryIndex !== -1) {
      this.memories.splice(memoryIndex, 1);
      this.version++;
      await this.save();
      return true;
    }

    return false;
  }

  /**
   * Clear all memories
   */
  async clear(): Promise<void> {
    this.memories = [];
    this.version++;
    await this.save();
  }

  /**
   * Get the current version (for cache invalidation)
   */
  getVersion(): number {
    return this.version;
  }

  /**
   * Get memories formatted for system prompt
   */
  async getForPrompt(): Promise<string | null> {
    await this.load();

    if (this.memories.length === 0) {
      return null;
    }

    const lines = this.memories.map((m) => `- ${m.content}`);
    return `## Remembered Context\nThe user has asked you to remember the following:\n${lines.join("\n")}`;
  }
}

export const memoryManager = new MemoryManager();

