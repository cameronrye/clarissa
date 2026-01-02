import { z } from "zod";
import { defineTool } from "./base.ts";
import { CodebaseIndexer } from "../index/codebase-index.ts";
import { providerRegistry } from "../llm/providers/index.ts";

/**
 * Semantic search tool - uses embeddings to find relevant code
 */
export const semanticSearchTool = defineTool({
  name: "semantic_search",
  description:
    "Search the codebase using natural language. Finds code semantically related to your query, not just exact matches. Requires the codebase to be indexed first with 'clarissa index'.",
  category: "file",
  priority: 2,
  parameters: z.object({
    query: z.string().describe("Natural language description of what you're looking for"),
    maxResults: z
      .number()
      .int()
      .min(1)
      .max(20)
      .optional()
      .default(5)
      .describe("Maximum results to return (default: 5)"),
    minScore: z
      .number()
      .min(0)
      .max(1)
      .optional()
      .default(0.3)
      .describe("Minimum similarity score 0-1 (default: 0.3)"),
  }),
  execute: async ({ query, maxResults = 5, minScore = 0.3 }) => {
    try {
      const rootPath = process.cwd();
      const indexer = new CodebaseIndexer(rootPath);

      // Try to load existing index
      const loaded = await indexer.load();
      if (!loaded || !indexer.isLoaded()) {
        return {
          error: true,
          message: "No codebase index found. Run 'clarissa index' first to index the codebase.",
          results: [],
        };
      }

      // Get local-llama provider for query embedding
      const provider = providerRegistry.getProvider("local-llama");
      if (!provider) {
        return {
          error: true,
          message: "local-llama provider not available. Semantic search requires a local model.",
          results: [],
        };
      }

      const status = await provider.checkAvailability();
      if (!status.available) {
        return {
          error: true,
          message: `local-llama provider not available: ${status.reason}`,
          results: [],
        };
      }

      await provider.initialize?.();
      indexer.setEmbedder(provider);

      // Perform search
      const results = await indexer.search(query, maxResults, minScore);

      if (results.length === 0) {
        return {
          query,
          message: "No results found matching your query.",
          results: [],
        };
      }

      return {
        query,
        resultCount: results.length,
        results: results.map((r) => ({
          file: r.relativePath,
          lines: `${r.startLine}-${r.endLine}`,
          score: Math.round(r.score * 100),
          preview: r.content.split("\n").slice(0, 5).join("\n"),
        })),
      };
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unknown error";
      return {
        error: true,
        message: `Semantic search failed: ${message}`,
        results: [],
      };
    }
  },
});

