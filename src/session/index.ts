import { join } from "path";
import { homedir } from "os";
import { mkdir, readdir, rm } from "fs/promises";
import type { Message } from "../llm/types.ts";

const SESSION_DIR = join(homedir(), ".clarissa", "sessions");

export interface Session {
  id: string;
  name: string;
  createdAt: string;
  updatedAt: string;
  messages: Message[];
}

/**
 * Session manager for persisting conversations
 */
class SessionManager {
  private currentSession: Session | null = null;

  /**
   * Ensure session directory exists
   */
  private async ensureDir(): Promise<void> {
    await mkdir(SESSION_DIR, { recursive: true });
  }

  /**
   * Generate a unique session ID
   */
  private generateId(): string {
    return `session_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
  }

  /**
   * Validate session ID to prevent path traversal
   */
  private validateId(id: string): void {
    // Only allow alphanumeric, underscore, and hyphen characters
    if (!/^[a-zA-Z0-9_-]+$/.test(id)) {
      throw new Error("Invalid session ID: contains disallowed characters");
    }
    // Prevent path traversal attempts
    if (id.includes("..") || id.includes("/") || id.includes("\\")) {
      throw new Error("Invalid session ID: path traversal not allowed");
    }
  }

  /**
   * Get session file path
   */
  private getPath(id: string): string {
    this.validateId(id);
    return join(SESSION_DIR, `${id}.json`);
  }

  /**
   * Create a new session
   */
  async create(name?: string): Promise<Session> {
    await this.ensureDir();

    const id = this.generateId();
    const now = new Date().toISOString();

    this.currentSession = {
      id,
      name: name || `Session ${new Date().toLocaleDateString()}`,
      createdAt: now,
      updatedAt: now,
      messages: [],
    };

    await this.save();
    return this.currentSession;
  }

  /**
   * Save current session to disk
   */
  async save(): Promise<void> {
    if (!this.currentSession) return;

    await this.ensureDir();
    this.currentSession.updatedAt = new Date().toISOString();

    const path = this.getPath(this.currentSession.id);
    await Bun.write(path, JSON.stringify(this.currentSession, null, 2));
  }

  /**
   * Load a session by ID
   */
  async load(id: string): Promise<Session | null> {
    try {
      const path = this.getPath(id);
      const file = Bun.file(path);

      if (!(await file.exists())) {
        return null;
      }

      const content = await file.json();
      this.currentSession = content as Session;
      return this.currentSession;
    } catch {
      return null;
    }
  }

  /**
   * List all sessions
   */
  async list(): Promise<Array<{ id: string; name: string; updatedAt: string }>> {
    await this.ensureDir();

    try {
      const files = await readdir(SESSION_DIR);
      const sessions: Array<{ id: string; name: string; updatedAt: string }> = [];

      for (const file of files) {
        if (!file.endsWith(".json")) continue;

        try {
          const path = join(SESSION_DIR, file);
          const content = await Bun.file(path).json();
          sessions.push({
            id: content.id,
            name: content.name,
            updatedAt: content.updatedAt,
          });
        } catch {
          continue;
        }
      }

      return sessions.sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
    } catch {
      return [];
    }
  }

  /**
   * Update messages in current session
   */
  updateMessages(messages: Message[]): void {
    if (this.currentSession) {
      this.currentSession.messages = messages;
    }
  }

  /**
   * Get current session
   */
  getCurrent(): Session | null {
    return this.currentSession;
  }

  /**
   * Get messages from current session
   */
  getMessages(): Message[] {
    return this.currentSession?.messages || [];
  }

  /**
   * Delete a session by ID
   */
  async delete(id: string): Promise<boolean> {
    try {
      const path = this.getPath(id);
      const file = Bun.file(path);

      if (!(await file.exists())) {
        return false;
      }

      await rm(path);

      // Clear current session if it was the deleted one
      if (this.currentSession?.id === id) {
        this.currentSession = null;
      }

      return true;
    } catch {
      return false;
    }
  }
}

export const sessionManager = new SessionManager();

