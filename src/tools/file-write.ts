import { z } from "zod";
import { defineTool } from "./base.ts";
import { dirname } from "path";
import { mkdir } from "fs/promises";
import { getSecurePaths } from "./security.ts";

/**
 * Write file tool - create or overwrite files
 */
export const writeFileTool = defineTool({
  name: "write_file",
  description:
    "Write content to a file, creating it if it doesn't exist or overwriting if it does. Creates parent directories as needed. Use this to create new files or completely replace file contents.",
  category: "file",
  requiresConfirmation: true,
  parameters: z.object({
    path: z.string().describe("Path to the file to write (relative to current directory)"),
    content: z.string().describe("The content to write to the file"),
  }),
  execute: async ({ path, content }) => {
    try {
      // Security check with canonical path resolution
      const { absolutePath, relativePath } = getSecurePaths(path);

      // Create parent directories if needed
      const dir = dirname(absolutePath);
      await mkdir(dir, { recursive: true });

      // Check if file exists for reporting
      const file = Bun.file(absolutePath);
      const existed = await file.exists();

      // Write the file
      await Bun.write(absolutePath, content);

      const lines = content.split("\n").length;
      const bytes = Buffer.byteLength(content, "utf8");

      return {
        path: relativePath,
        action: existed ? "updated" : "created",
        lines,
        bytes,
        message: `Successfully ${existed ? "updated" : "created"} ${relativePath} (${lines} lines, ${bytes} bytes)`,
      };
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unknown error";
      throw new Error(`Failed to write file: ${message}`);
    }
  },
});

