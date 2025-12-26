import { join } from "path";
import { homedir } from "os";
import { mkdir } from "fs/promises";
import { z } from "zod";

const MEMORY_FILE = join(homedir(), ".clarissa", "memories.json");

/**
 * Schema for validating memory data from disk
 */
const memorySchema = z.object({
  id: z.string(),
  content: z.string(),
  createdAt: z.string(),
});

const memoriesArraySchema = z.array(memorySchema);

/** Maximum number of memories to store (matches iOS) */
const MAX_MEMORIES = 100;

/** Maximum number of recent memories to include in prompt (matches iOS) */
const MAX_MEMORIES_FOR_PROMPT = 20;

/** Maximum character length for a single memory (matches iOS) */
const MAX_MEMORY_LENGTH = 500;

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
   * Normalize content for duplicate comparison
   */
  private normalizeContent(content: string): string {
    return content.toLowerCase().trim();
  }

  /**
   * Check if a memory with similar content already exists
   */
  private isDuplicate(content: string): boolean {
    const normalized = this.normalizeContent(content);
    return this.memories.some(
      (m) => this.normalizeContent(m.content) === normalized
    );
  }

  /**
   * Sanitize memory content to prevent prompt injection attacks (matches iOS)
   * Removes instruction override attempts and limits length
   */
  private sanitize(content: string): string {
    let sanitized = content.trim();

    // Remove potential instruction override attempts (case-insensitive)
    const dangerousPatterns = [
      /SYSTEM:/gi,
      /INSTRUCTIONS:/gi,
      /IGNORE\s*(PREVIOUS|ALL|ABOVE)/gi,
      /OVERRIDE/gi,
      /DISREGARD/gi,
      /FORGET\s*(PREVIOUS|ALL|ABOVE)/gi,
      /NEW\s*INSTRUCTIONS:/gi,
      /\[SYSTEM\]/gi,
      /\[INST\]/gi,
      /<\|im_start\|>/gi,
      /<\|im_end\|>/gi,
    ];

    for (const pattern of dangerousPatterns) {
      sanitized = sanitized.replace(pattern, "");
    }

    // Remove markdown headers that could look like new sections
    sanitized = sanitized.replace(/^#{1,6}\s+/gm, "");

    // Limit length to prevent context overflow
    if (sanitized.length > MAX_MEMORY_LENGTH) {
      sanitized = sanitized.slice(0, MAX_MEMORY_LENGTH) + "...";
    }

    return sanitized;
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

        // Validate memory data against schema to prevent corrupted files
        // from causing runtime errors
        const result = memoriesArraySchema.safeParse(content);
        if (!result.success) {
          console.error("Invalid memory data:", result.error.message);
          this.memories = [];
        } else {
          this.memories = result.data as Memory[];
        }
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
   * Returns null if memory is a duplicate
   */
  async add(content: string): Promise<Memory | null> {
    await this.load();

    // Check for duplicates (iOS pattern)
    if (this.isDuplicate(content)) {
      return null;
    }

    // Sanitize content before storing (iOS pattern)
    const sanitizedContent = this.sanitize(content);

    const memory: Memory = {
      id: this.generateId(),
      content: sanitizedContent,
      createdAt: new Date().toISOString(),
    };

    this.memories.push(memory);

    // Trim old memories if exceeding max (iOS pattern)
    if (this.memories.length > MAX_MEMORIES) {
      const toRemove = this.memories.length - MAX_MEMORIES;
      this.memories.splice(0, toRemove);
    }

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
   * Only includes most recent memories to avoid context overflow (iOS pattern)
   */
  async getForPrompt(): Promise<string | null> {
    await this.load();

    if (this.memories.length === 0) {
      return null;
    }

    // Take only most recent memories for prompt (iOS pattern)
    const recentMemories = this.memories.slice(-MAX_MEMORIES_FOR_PROMPT);
    const lines = recentMemories.map((m) => `- ${m.content}`);
    return `## Remembered Context\nThe user has asked you to remember the following:\n${lines.join("\n")}`;
  }
}

export const memoryManager = new MemoryManager();

