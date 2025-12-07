import { z } from "zod";
import { defineTool } from "./base.ts";
import { resolve, relative } from "path";

/**
 * Patch file tool - string replacement editing
 */
export const patchFileTool = defineTool({
  name: "patch_file",
  description:
    "Edit a file by replacing a specific string with new content. The old string must match exactly (including whitespace). Use this for targeted edits to existing files.",
  category: "file",
  requiresConfirmation: true,
  parameters: z.object({
    path: z.string().describe("Path to the file to edit (relative to current directory)"),
    oldStr: z
      .string()
      .describe("The exact string to find and replace (must match exactly, including whitespace)"),
    newStr: z
      .string()
      .describe("The new string to replace it with (can be empty to delete)"),
  }),
  execute: async ({ path, oldStr, newStr }) => {
    try {
      const absolutePath = resolve(process.cwd(), path);
      const relativePath = relative(process.cwd(), absolutePath);

      // Security check
      if (relativePath.startsWith("..")) {
        throw new Error("Cannot edit files outside the current directory");
      }

      const file = Bun.file(absolutePath);
      const exists = await file.exists();

      if (!exists) {
        throw new Error(`File not found: ${path}`);
      }

      const content = await file.text();

      // Count occurrences
      const occurrences = content.split(oldStr).length - 1;

      if (occurrences === 0) {
        throw new Error(
          `String not found in file. Make sure the old string matches exactly (including whitespace and line endings).`
        );
      }

      if (occurrences > 1) {
        throw new Error(
          `Found ${occurrences} occurrences of the string. Please provide a more specific string that matches exactly once.`
        );
      }

      // Perform replacement
      const newContent = content.replace(oldStr, newStr);

      // Write back
      await Bun.write(absolutePath, newContent);

      // Calculate diff stats
      const oldLines = oldStr.split("\n").length;
      const newLines = newStr.split("\n").length;

      return {
        path: relativePath,
        linesRemoved: oldLines,
        linesAdded: newLines,
        netChange: newLines - oldLines,
        message: `Successfully patched ${relativePath}: replaced ${oldLines} line(s) with ${newLines} line(s)`,
      };
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unknown error";
      throw new Error(`Failed to patch file: ${message}`);
    }
  },
});

