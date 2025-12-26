import { join } from "path";
import { existsSync } from "fs";
import { z } from "zod";
import { CONFIG_DIR } from "../config/index.ts";

const HISTORY_FILE = join(CONFIG_DIR, "history.json");
const MAX_HISTORY_ENTRIES = 100;

export interface HistoryEntry {
  query: string;
  response: string;
  model: string;
  timestamp: string;
}

/**
 * Schema for validating history data from disk
 */
const historyEntrySchema = z.object({
  query: z.string(),
  response: z.string(),
  model: z.string(),
  timestamp: z.string(),
});

const historyDataSchema = z.object({
  entries: z.array(historyEntrySchema),
});

type HistoryData = z.infer<typeof historyDataSchema>;

/**
 * Simple async mutex for serializing file operations
 */
class AsyncMutex {
  private queue: (() => void)[] = [];
  private locked = false;

  async acquire(): Promise<void> {
    if (!this.locked) {
      this.locked = true;
      return;
    }
    return new Promise<void>((resolve) => {
      this.queue.push(resolve);
    });
  }

  release(): void {
    const next = this.queue.shift();
    if (next) {
      next();
    } else {
      this.locked = false;
    }
  }
}

/**
 * History manager for persisting one-shot queries
 */
class HistoryManager {
  private entries: HistoryEntry[] = [];
  private loaded = false;
  private mutex = new AsyncMutex();

  /**
   * Load history from disk
   */
  private async load(): Promise<void> {
    if (this.loaded) return;

    try {
      if (existsSync(HISTORY_FILE)) {
        const content = JSON.parse(await Bun.file(HISTORY_FILE).text());

        // Validate history data against schema to prevent corrupted files
        // from causing runtime errors
        const result = historyDataSchema.safeParse(content);
        if (!result.success) {
          console.error("Invalid history data:", result.error.message);
          this.entries = [];
        } else {
          this.entries = result.data.entries;
        }
      }
    } catch {
      this.entries = [];
    }

    this.loaded = true;
  }

  /**
   * Save history to disk
   */
  private async save(): Promise<void> {
    const data: HistoryData = { entries: this.entries };
    await Bun.write(HISTORY_FILE, JSON.stringify(data, null, 2) + "\n");
  }

  /**
   * Add a new history entry (thread-safe)
   */
  async add(query: string, response: string, model: string): Promise<void> {
    await this.mutex.acquire();
    try {
      await this.load();

      const entry: HistoryEntry = {
        query: query.trim(),
        response: response.trim(),
        model,
        timestamp: new Date().toISOString(),
      };

      this.entries.unshift(entry);

      // Keep only the most recent entries
      if (this.entries.length > MAX_HISTORY_ENTRIES) {
        this.entries = this.entries.slice(0, MAX_HISTORY_ENTRIES);
      }

      await this.save();
    } finally {
      this.mutex.release();
    }
  }

  /**
   * Get all history entries (thread-safe)
   */
  async list(): Promise<HistoryEntry[]> {
    await this.mutex.acquire();
    try {
      await this.load();
      return [...this.entries];
    } finally {
      this.mutex.release();
    }
  }

  /**
   * Get recent entries (thread-safe)
   */
  async getRecent(count: number = 10): Promise<HistoryEntry[]> {
    await this.mutex.acquire();
    try {
      await this.load();
      return this.entries.slice(0, count);
    } finally {
      this.mutex.release();
    }
  }

  /**
   * Clear all history (thread-safe)
   */
  async clear(): Promise<void> {
    await this.mutex.acquire();
    try {
      this.entries = [];
      await this.save();
    } finally {
      this.mutex.release();
    }
  }
}

export const historyManager = new HistoryManager();

