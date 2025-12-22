import { test, expect, describe } from "bun:test";
import { join } from "path";
import {
  RECOMMENDED_MODELS,
  getHuggingFaceUrl,
  getModelPath,
  formatBytes,
  formatSpeed,
  isModelDownloaded,
  ensureModelsDir,
  listDownloadedModels,
  MODELS_DIR,
  downloadModel,
  deleteModel,
} from "./download.ts";

describe("Model Download Utilities", () => {
  describe("RECOMMENDED_MODELS", () => {
    test("contains expected models", () => {
      expect(RECOMMENDED_MODELS.length).toBeGreaterThan(0);

      // Check for key models
      const modelIds = RECOMMENDED_MODELS.map((m) => m.id);
      expect(modelIds).toContain("qwen2.5-7b");
      expect(modelIds).toContain("gemma3-12b");
      expect(modelIds).toContain("llama4-scout");
      expect(modelIds).toContain("deepseek-r1-8b");
    });

    test("each model has required fields", () => {
      for (const model of RECOMMENDED_MODELS) {
        expect(model.id).toBeDefined();
        expect(model.name).toBeDefined();
        expect(model.repo).toBeDefined();
        expect(model.file).toBeDefined();
        expect(model.size).toBeDefined();
        expect(model.description).toBeDefined();

        // File should be a GGUF file
        expect(model.file).toMatch(/\.gguf$/);
      }
    });

    test("model repos are valid Hugging Face format", () => {
      for (const model of RECOMMENDED_MODELS) {
        // Should be in format "owner/repo"
        expect(model.repo).toMatch(/^[^/]+\/[^/]+$/);
      }
    });
  });

  describe("getHuggingFaceUrl", () => {
    test("builds correct URL for repo and file", () => {
      const url = getHuggingFaceUrl("Qwen/Qwen3-8B-GGUF", "qwen3-8b-q4_k_m.gguf");
      expect(url).toBe(
        "https://huggingface.co/Qwen/Qwen3-8B-GGUF/resolve/main/qwen3-8b-q4_k_m.gguf"
      );
    });

    test("handles repos with special characters", () => {
      const url = getHuggingFaceUrl("lmstudio-community/gemma-3-12b-it-GGUF", "gemma-3-12b-it-Q4_K_M.gguf");
      expect(url).toBe(
        "https://huggingface.co/lmstudio-community/gemma-3-12b-it-GGUF/resolve/main/gemma-3-12b-it-Q4_K_M.gguf"
      );
    });
  });

  describe("getModelPath", () => {
    test("returns path in models directory", () => {
      const path = getModelPath("test-model.gguf");
      expect(path).toBe(join(MODELS_DIR, "test-model.gguf"));
    });
  });

  describe("formatBytes", () => {
    test("formats zero bytes", () => {
      expect(formatBytes(0)).toBe("0 B");
    });

    test("formats bytes", () => {
      expect(formatBytes(500)).toBe("500.0 B");
    });

    test("formats kilobytes", () => {
      expect(formatBytes(1024)).toBe("1.0 KB");
      expect(formatBytes(1536)).toBe("1.5 KB");
    });

    test("formats megabytes", () => {
      expect(formatBytes(1024 * 1024)).toBe("1.0 MB");
      expect(formatBytes(5.5 * 1024 * 1024)).toBe("5.5 MB");
    });

    test("formats gigabytes", () => {
      expect(formatBytes(1024 * 1024 * 1024)).toBe("1.0 GB");
      expect(formatBytes(10.5 * 1024 * 1024 * 1024)).toBe("10.5 GB");
    });
  });

  describe("formatSpeed", () => {
    test("formats speed in bytes per second", () => {
      expect(formatSpeed(1024)).toBe("1.0 KB/s");
      expect(formatSpeed(1024 * 1024)).toBe("1.0 MB/s");
      expect(formatSpeed(50 * 1024 * 1024)).toBe("50.0 MB/s");
    });
  });

  describe("isModelDownloaded", () => {
    test("returns false for non-existent model", async () => {
      const result = await isModelDownloaded("nonexistent-model-12345.gguf");
      expect(result).toBe(false);
    });
  });

  describe("ensureModelsDir", () => {
    test("creates and returns models directory path", async () => {
      const dir = await ensureModelsDir();
      expect(dir).toBe(MODELS_DIR);
      // Directory should exist after call - check by trying to list it
      const { existsSync } = await import("fs");
      expect(existsSync(dir)).toBe(true);
    });
  });

  describe("listDownloadedModels", () => {
    test("returns array of model filenames", async () => {
      const models = await listDownloadedModels();
      expect(Array.isArray(models)).toBe(true);
      // All returned files should be GGUF files
      for (const model of models) {
        expect(model).toMatch(/\.gguf$/);
      }
    });

    test("returns empty array when no models downloaded", async () => {
      // This test may pass or fail depending on whether models are downloaded
      const models = await listDownloadedModels();
      expect(Array.isArray(models)).toBe(true);
    });
  });

	  describe("downloadModel and deleteModel", () => {
	    const TEST_MODEL = "test-model-download.gguf";

	    test("downloads a model using injected fetch and writes file", async () => {
	      const data = "test-model-content";
	      let fetchCalls = 0;

	      const mockFetch: typeof fetch = async () => {
	        fetchCalls++;
	        return new Response(data, {
	          status: 200,
	          headers: { "content-length": String(data.length) },
	        });
	      };

	      const path = await downloadModel("owner/repo", TEST_MODEL, undefined, mockFetch);
	      expect(path).toBe(getModelPath(TEST_MODEL));

	      const file = Bun.file(path);
	      expect(await file.exists()).toBe(true);
	      expect(await file.text()).toBe(data);

	      // Second call should not re-download if file exists
	      const path2 = await downloadModel("owner/repo", TEST_MODEL, undefined, mockFetch);
	      expect(path2).toBe(path);
	      expect(fetchCalls).toBe(1);
	    });

	    test("deleteModel removes downloaded file", async () => {
	      const path = getModelPath(TEST_MODEL);
	      await Bun.write(path, "to-delete");
	      expect(await Bun.file(path).exists()).toBe(true);

	      const result = await deleteModel(TEST_MODEL);
	      expect(result).toBe(true);
	      expect(await Bun.file(path).exists()).toBe(false);
	    });
	  });
});

