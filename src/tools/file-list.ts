import { z } from "zod";
import { defineTool } from "./base.ts";
import { join } from "path";
import { readdir, stat } from "fs/promises";
import { getSecurePaths } from "./security.ts";

/**
 * List directory tool - tree view with filtering
 */
export const listDirectoryTool = defineTool({
  name: "list_directory",
  description:
    "List files and directories in a path. Shows a tree view with file types and sizes. Use this to explore the project structure.",
  parameters: z.object({
    path: z
      .string()
      .optional()
      .default(".")
      .describe("Path to list (relative to current directory, defaults to '.')"),
    depth: z
      .number()
      .int()
      .min(1)
      .max(5)
      .optional()
      .default(2)
      .describe("Maximum depth to recurse (1-5, default: 2)"),
    showHidden: z
      .boolean()
      .optional()
      .default(false)
      .describe("Include hidden files (starting with .)"),
  }),
  execute: async ({ path = ".", depth = 2, showHidden = false }) => {
    try {
      // Security check with canonical path resolution
      const { absolutePath, relativePath } = getSecurePaths(path);

      const entries: string[] = [];
      const ignoredDirs = new Set(["node_modules", ".git", "dist", "build", ".next", "__pycache__"]);

      async function listDir(dirPath: string, currentDepth: number, prefix: string): Promise<void> {
        if (currentDepth > depth) return;

        let items: string[];
        try {
          items = await readdir(dirPath);
        } catch {
          return;
        }

        // Filter and sort
        const filtered = items
          .filter((item) => showHidden || !item.startsWith("."))
          .filter((item) => !ignoredDirs.has(item))
          .sort((a, b) => a.localeCompare(b));

        for (let i = 0; i < filtered.length; i++) {
          const item = filtered[i]!;
          const itemPath = join(dirPath, item);
          const isLast = i === filtered.length - 1;
          const connector = isLast ? "└── " : "├── ";
          const childPrefix = isLast ? "    " : "│   ";

          try {
            const stats = await stat(itemPath);
            const isDir = stats.isDirectory();

            if (isDir) {
              entries.push(`${prefix}${connector}${item}/`);
              await listDir(itemPath, currentDepth + 1, prefix + childPrefix);
            } else {
              const size = formatSize(stats.size);
              entries.push(`${prefix}${connector}${item} (${size})`);
            }
          } catch {
            entries.push(`${prefix}${connector}${item} [error]`);
          }
        }
      }

      entries.push(relativePath === "." ? "./" : `${relativePath}/`);
      await listDir(absolutePath, 1, "");

      return {
        path: relativePath,
        depth,
        tree: entries.join("\n"),
      };
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unknown error";
      throw new Error(`Failed to list directory: ${message}`);
    }
  },
});

function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes}B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)}KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)}MB`;
}

