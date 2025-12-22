import { z } from "zod";
import { defineTool } from "./base.ts";
import { getSecurePaths } from "./security.ts";

/**
 * Read file tool - view files with line numbers and optional range
 */
export const readFileTool = defineTool({
  name: "read_file",
  description:
    "Read a file and return its contents with line numbers. Can optionally read a specific range of lines. Use this to view source code, configuration files, or any text file.",
  parameters: z.object({
    path: z.string().describe("Path to the file to read (relative to current directory)"),
    startLine: z
      .number()
      .int()
      .positive()
      .optional()
      .describe("Starting line number (1-based, inclusive)"),
    endLine: z
      .number()
      .int()
      .refine((n) => n === -1 || n > 0, {
        message: "endLine must be a positive integer or -1 for end of file",
      })
      .optional()
      .describe("Ending line number (1-based, inclusive). Use -1 for end of file"),
  }),
  execute: async ({ path, startLine, endLine }) => {
    try {
      // Security check with canonical path resolution
      const { absolutePath, relativePath } = getSecurePaths(path);

      const file = Bun.file(absolutePath);
      const exists = await file.exists();

      if (!exists) {
        throw new Error(`File not found: ${path}`);
      }

      const content = await file.text();
      const lines = content.split("\n");
      const totalLines = lines.length;

      // Determine range
      const start = startLine ? Math.max(1, startLine) : 1;
      const end = endLine === -1 ? totalLines : endLine ? Math.min(endLine, totalLines) : totalLines;

      if (start > totalLines) {
        throw new Error(`Start line ${start} exceeds file length (${totalLines} lines)`);
      }

      // Extract lines (convert to 0-based index)
      const selectedLines = lines.slice(start - 1, end);

      // Format with line numbers
      const maxLineNumWidth = String(end).length;
      const formatted = selectedLines
        .map((line, i) => {
          const lineNum = String(start + i).padStart(maxLineNumWidth, " ");
          return `${lineNum} | ${line}`;
        })
        .join("\n");

      return {
        path: relativePath,
        totalLines,
        displayedRange: { start, end },
        content: formatted,
      };
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unknown error";
      throw new Error(`Failed to read file: ${message}`);
    }
  },
});

