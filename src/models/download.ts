/**
 * Model Download Helper
 *
 * Downloads GGUF models from Hugging Face for local inference.
 * Supports progress tracking and config integration.
 */

import { join } from "path";
import { homedir } from "os";
import { mkdir, rename, rm } from "fs/promises";

// Default models directory
export const MODELS_DIR = join(homedir(), ".clarissa", "models");

/**
 * Best GGUF models for December 2025
 * Curated for local inference performance and quality
 */
export const RECOMMENDED_MODELS = [
  // Qwen 2.5 - Top performer for coding and tool use (bartowski quantizations)
  {
    id: "qwen2.5-7b-f16",
    name: "Qwen 2.5 7B Instruct F16",
    repo: "bartowski/Qwen2.5-7B-Instruct-GGUF",
    file: "Qwen2.5-7B-Instruct-f16.gguf",
    size: "15.2 GB",
    description: "Full precision, best quality for tool use",
  },
  {
    id: "qwen2.5-7b",
    name: "Qwen 2.5 7B Instruct Q4_K_M",
    repo: "bartowski/Qwen2.5-7B-Instruct-GGUF",
    file: "Qwen2.5-7B-Instruct-Q4_K_M.gguf",
    size: "4.7 GB",
    description: "Best balance of quality and size for tool use",
  },
  // Gemma 3 - Google's top-tier models
  {
    id: "gemma3-12b",
    name: "Gemma 3 12B Instruct",
    repo: "lmstudio-community/gemma-3-12b-it-GGUF",
    file: "gemma-3-12b-it-Q4_K_M.gguf",
    size: "7.3 GB",
    description: "Google's excellent general-purpose model",
  },
  {
    id: "gemma3-4b",
    name: "Gemma 3 4B Instruct",
    repo: "lmstudio-community/gemma-3-4b-it-GGUF",
    file: "gemma-3-4b-it-Q4_K_M.gguf",
    size: "2.5 GB",
    description: "Compact Google model, great quality/size ratio",
  },
  // Llama 4 Scout - Meta's newest with 10M context
  {
    id: "llama4-scout",
    name: "Llama 4 Scout 17B (MoE)",
    repo: "unsloth/Llama-4-Scout-17B-16E-Instruct-GGUF",
    file: "Llama-4-Scout-17B-16E-Instruct-UD-Q4_K_XL.gguf",
    size: "12.0 GB",
    description: "Meta's MoE model with 10M context window",
  },
  // DeepSeek R1 - Reasoning specialist
  {
    id: "deepseek-r1-8b",
    name: "DeepSeek R1 Distill 8B",
    repo: "unsloth/DeepSeek-R1-Distill-Llama-8B-GGUF",
    file: "DeepSeek-R1-Distill-Llama-8B-Q4_K_M.gguf",
    size: "4.9 GB",
    description: "Strong reasoning and chain-of-thought",
  },
  // OpenAI GPT-OSS - Official open-source model
  {
    id: "gpt-oss-20b",
    name: "OpenAI GPT-OSS 20B",
    repo: "ggml-org/gpt-oss-20b-GGUF",
    file: "gpt-oss-20b-mxfp4.gguf",
    size: "10.5 GB",
    description: "OpenAI's open-source reasoning model",
  },
  // Qwen 3 Coder - Agentic coding specialist
  {
    id: "qwen3-coder",
    name: "Qwen 3 Coder 30B-A3B (MoE)",
    repo: "unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF",
    file: "Qwen3-Coder-30B-A3B-Instruct-UD-Q4_K_XL.gguf",
    size: "11.0 GB",
    description: "Best for agentic coding with function calls",
  },
];

export type RecommendedModel = (typeof RECOMMENDED_MODELS)[number];

/**
 * Progress callback for download updates
 */
export type DownloadProgress = {
  downloaded: number;
  total: number;
  percent: number;
  speed: number; // bytes per second
};

/**
 * Ensure models directory exists
 */
export async function ensureModelsDir(): Promise<string> {
  await mkdir(MODELS_DIR, { recursive: true });
  return MODELS_DIR;
}

/**
 * Get the local path for a model
 */
export function getModelPath(filename: string): string {
  return join(MODELS_DIR, filename);
}

/**
 * Check if a model is already downloaded
 */
export async function isModelDownloaded(filename: string): Promise<boolean> {
  const path = getModelPath(filename);
  return await Bun.file(path).exists();
}

/**
 * Build Hugging Face download URL
 */
export function getHuggingFaceUrl(repo: string, file: string): string {
  return `https://huggingface.co/${repo}/resolve/main/${file}`;
}

/**
 * Download a model from Hugging Face with progress tracking
 */
export async function downloadModel(
  repo: string,
  file: string,
  onProgress?: (progress: DownloadProgress) => void,
  fetchImpl: typeof fetch = fetch
): Promise<string> {
  await ensureModelsDir();

  const url = getHuggingFaceUrl(repo, file);
  const destPath = getModelPath(file);
  const tempPath = destPath + ".tmp";

  // Check if already exists
  if (await Bun.file(destPath).exists()) {
    return destPath;
  }

  const response = await fetchImpl(url, {
    headers: {
      "User-Agent": "Clarissa/1.0 (AI Assistant)",
    },
  });

  if (!response.ok) {
    throw new Error(`Download failed: ${response.status} ${response.statusText}`);
  }

  const contentLength = response.headers.get("content-length");
  const total = contentLength ? parseInt(contentLength, 10) : 0;

  // Warn if content-length is missing (progress tracking won't work accurately)
  if (!contentLength) {
    console.warn("Warning: Server did not provide Content-Length header. Download progress may be inaccurate.");
  }

  // Stream directly to file to avoid memory issues with large files
  const reader = response.body?.getReader();
  if (!reader) {
    throw new Error("Failed to get response stream");
  }

  // Open file for writing
  const fileHandle = Bun.file(tempPath).writer();

  let downloaded = 0;
  let lastUpdate = Date.now();
  let lastDownloaded = 0;
  let success = false;

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      // Write chunk directly to file
      fileHandle.write(value);
      downloaded += value.length;

      // Report progress every 100ms
      const now = Date.now();
      if (onProgress && now - lastUpdate >= 100) {
        const elapsed = (now - lastUpdate) / 1000;
        const speed = (downloaded - lastDownloaded) / elapsed;
        onProgress({
          downloaded,
          total,
          percent: total > 0 ? (downloaded / total) * 100 : 0,
          speed,
        });
        lastUpdate = now;
        lastDownloaded = downloaded;
      }
    }

    // Flush and close
    await fileHandle.end();

    // Final progress update
    if (onProgress) {
      onProgress({
        downloaded,
        total,
        percent: 100,
        speed: 0,
      });
    }

    // Rename temp file to final destination (cross-platform)
    await rename(tempPath, destPath);

    success = true;
    return destPath;
  } finally {
    // Always attempt to close the file handle
    if (!success) {
      try {
        await fileHandle.end();
      } catch {
        // Ignore close errors during cleanup
      }
    }
    // Clean up temp file on error
    if (!success) {
      try {
        await rm(tempPath, { force: true });
      } catch {
        // Ignore cleanup errors
      }
    }
  }
}

/**
 * Format bytes to human-readable string
 */
export function formatBytes(bytes: number): string {
  if (bytes === 0) return "0 B";
  const k = 1024;
  const sizes = ["B", "KB", "MB", "GB", "TB"];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return `${(bytes / Math.pow(k, i)).toFixed(1)} ${sizes[i]}`;
}

/**
 * Format download speed
 */
export function formatSpeed(bytesPerSecond: number): string {
  return `${formatBytes(bytesPerSecond)}/s`;
}

/**
 * List downloaded models
 */
export async function listDownloadedModels(): Promise<string[]> {
  try {
    const dir = await ensureModelsDir();
    const files: string[] = [];

    for await (const entry of new Bun.Glob("*.gguf").scan(dir)) {
      files.push(entry);
    }

    return files;
  } catch {
    return [];
  }
}

/**
 * Delete a downloaded model
 */
export async function deleteModel(filename: string): Promise<boolean> {
  const path = getModelPath(filename);
  try {
    if (await Bun.file(path).exists()) {
      await rm(path, { force: true });
    }
    return true;
  } catch {
    return false;
  }
}

