/**
 * Codebase Index - Indexes source files using local embeddings for semantic search.
 */

import { join, relative, extname } from "path";
import { homedir } from "os";
import { mkdir } from "fs/promises";
import type { LLMProvider } from "../llm/providers/types.ts";

export const INDEX_DIR = join(homedir(), ".clarissa", "index");

export interface IndexedFile {
  path: string;
  relativePath: string;
  hash: string;
  chunks: IndexedChunk[];
  indexedAt: number;
}

export interface IndexedChunk {
  id: string;
  content: string;
  startLine: number;
  endLine: number;
  embedding: number[];
}

export interface SearchResult {
  filePath: string;
  relativePath: string;
  content: string;
  startLine: number;
  endLine: number;
  score: number;
}

interface IndexMetadata {
  version: number;
  rootPath: string;
  fileCount: number;
  chunkCount: number;
  embeddingDimension: number;
  createdAt: number;
  updatedAt: number;
}

const INDEXABLE_EXTENSIONS = new Set([
  ".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".py", ".rb", ".rs", ".go",
  ".java", ".kt", ".scala", ".c", ".cpp", ".h", ".hpp", ".cs", ".swift",
  ".json", ".yaml", ".yml", ".toml", ".md", ".txt", ".sh", ".sql", ".css", ".html",
]);

const SKIP_DIRS = new Set([
  "node_modules", ".git", "dist", "build", ".next", "__pycache__", ".venv", "target", ".cache",
]);

export function cosineSimilarity(a: number[], b: number[]): number {
  if (a.length !== b.length) return 0;
  let dot = 0, normA = 0, normB = 0;
  for (let i = 0; i < a.length; i++) {
    dot += a[i]! * b[i]!;
    normA += a[i]! * a[i]!;
    normB += b[i]! * b[i]!;
  }
  const denom = Math.sqrt(normA) * Math.sqrt(normB);
  return denom === 0 ? 0 : dot / denom;
}

export function splitIntoChunks(content: string, maxSize = 1000, overlap = 100) {
  const lines = content.split("\n");
  const chunks: Array<{ content: string; startLine: number; endLine: number }> = [];
  let chunk: string[] = [], size = 0, start = 1;
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]!;
    if (size + line.length > maxSize && chunk.length > 0) {
      chunks.push({ content: chunk.join("\n"), startLine: start, endLine: start + chunk.length - 1 });
      const keep = Math.min(Math.ceil(overlap / (size / chunk.length)), chunk.length);
      chunk = chunk.slice(-keep);
      size = chunk.join("\n").length;
      start = i + 1 - keep;
    }
    chunk.push(line);
    size += line.length + 1;
  }
  if (chunk.length > 0) chunks.push({ content: chunk.join("\n"), startLine: start, endLine: lines.length });
  return chunks;
}

async function hashContent(content: string): Promise<string> {
  const hasher = new Bun.CryptoHasher("sha256");
  hasher.update(content);
  return hasher.digest("hex").slice(0, 16);
}

async function collectFiles(dir: string, root: string): Promise<string[]> {
  const entries = await Array.fromAsync(new Bun.Glob("**/*").scan({ cwd: dir, onlyFiles: true, absolute: true }));
  return entries.filter(e => {
    const rel = relative(root, e);
    if (rel.split("/").some(p => SKIP_DIRS.has(p))) return false;
    return INDEXABLE_EXTENSIONS.has(extname(e).toLowerCase());
  });
}

export class CodebaseIndexer {
  private rootPath: string;
  private indexPath: string;
  private metadata: IndexMetadata | null = null;
  private files: Map<string, IndexedFile> = new Map();
  private embedder: LLMProvider | null = null;
  private embeddingDim = 0;

  constructor(rootPath: string) {
    this.rootPath = rootPath;
    this.indexPath = join(INDEX_DIR, Bun.hash(rootPath).toString(16).slice(0, 8));
  }

  setEmbedder(provider: LLMProvider) { this.embedder = provider; }
  getStats() { return this.metadata; }
  isLoaded() { return this.files.size > 0; }

  async load(): Promise<boolean> {
    try {
      const meta = Bun.file(join(this.indexPath, "metadata.json"));
      if (!(await meta.exists())) return false;
      this.metadata = await meta.json();
      if (this.metadata?.rootPath !== this.rootPath) return false;
      const idx = Bun.file(join(this.indexPath, "index.json"));
      if (await idx.exists()) {
        const data = await idx.json() as IndexedFile[];
        this.files = new Map(data.map(f => [f.path, f]));
      }
      this.embeddingDim = this.metadata?.embeddingDimension ?? 0;
      return true;
    } catch { return false; }
  }

  async save(): Promise<void> {
    await mkdir(this.indexPath, { recursive: true });
    const meta: IndexMetadata = {
      version: 1, rootPath: this.rootPath, fileCount: this.files.size,
      chunkCount: [...this.files.values()].reduce((s, f) => s + f.chunks.length, 0),
      embeddingDimension: this.embeddingDim, createdAt: this.metadata?.createdAt ?? Date.now(), updatedAt: Date.now(),
    };
    await Bun.write(join(this.indexPath, "metadata.json"), JSON.stringify(meta, null, 2));
    await Bun.write(join(this.indexPath, "index.json"), JSON.stringify([...this.files.values()]));
    this.metadata = meta;
  }

  async index(onProgress?: (current: number, total: number, file: string) => void): Promise<{ indexed: number; skipped: number; errors: number }> {
    if (!this.embedder?.embed) throw new Error("No embedder set. Call setEmbedder() first.");
    const filePaths = await collectFiles(this.rootPath, this.rootPath);
    let indexed = 0, skipped = 0, errors = 0;

    for (let i = 0; i < filePaths.length; i++) {
      const filePath = filePaths[i]!;
      const relativePath = relative(this.rootPath, filePath);
      onProgress?.(i + 1, filePaths.length, relativePath);

      try {
        const content = await Bun.file(filePath).text();
        const hash = await hashContent(content);
        const existing = this.files.get(filePath);
        if (existing && existing.hash === hash) { skipped++; continue; }
        if (content.length > 100000) { skipped++; continue; }

        const rawChunks = splitIntoChunks(content);
        const chunkTexts = rawChunks.map(c => `File: ${relativePath}\n\n${c.content}`);
        const embeddings = await this.embedder.embed(chunkTexts);
        if (embeddings.length > 0 && this.embeddingDim === 0) this.embeddingDim = embeddings[0]!.length;

        const chunks: IndexedChunk[] = rawChunks.map((c, idx) => ({
          id: `${hash}-${idx}`, content: c.content, startLine: c.startLine, endLine: c.endLine, embedding: embeddings[idx]!,
        }));
        this.files.set(filePath, { path: filePath, relativePath, hash, chunks, indexedAt: Date.now() });
        indexed++;
      } catch (e) {
        if (process.env.DEBUG) console.error(`Error indexing ${relativePath}:`, e);
        errors++;
      }
    }
    await this.save();
    return { indexed, skipped, errors };
  }

  async search(query: string, topK = 10, minScore = 0.3): Promise<SearchResult[]> {
    if (!this.embedder?.embed) throw new Error("No embedder set.");
    if (this.files.size === 0) throw new Error("Index is empty. Run index() first.");

    const [queryEmbedding] = await this.embedder.embed([query]);
    if (!queryEmbedding) throw new Error("Failed to generate query embedding.");

    const results: SearchResult[] = [];
    for (const file of this.files.values()) {
      for (const chunk of file.chunks) {
        const score = cosineSimilarity(queryEmbedding, chunk.embedding);
        if (score >= minScore) {
          results.push({
            filePath: file.path, relativePath: file.relativePath,
            content: chunk.content, startLine: chunk.startLine, endLine: chunk.endLine, score,
          });
        }
      }
    }
    return results.sort((a, b) => b.score - a.score).slice(0, topK);
  }

  async clear(): Promise<void> {
    this.files.clear();
    this.metadata = null;
    try { await Bun.write(join(this.indexPath, "index.json"), "[]"); } catch {}
  }
}