/**
 * File Context References
 *
 * Parses @filename references in user prompts and expands them
 * to include file contents inline. Supports relative and absolute paths.
 *
 * Examples:
 *   @src/index.ts           -> Expands to file contents
 *   @./README.md            -> Relative path
 *   @/absolute/path.txt     -> Absolute path
 *   @package.json:1-50      -> Lines 1-50 only
 */

import { resolve, isAbsolute } from "path";

/**
 * Result of expanding file references
 */
export interface FileReferenceResult {
  /** The expanded message with file contents injected */
  expandedMessage: string;
  /** List of files that were successfully referenced */
  referencedFiles: string[];
  /** List of files that failed to load with error messages */
  failedFiles: Array<{ path: string; error: string }>;
}

/**
 * Regex to match @filename patterns
 * Matches: @path/to/file.ext or @path/to/file.ext:start-end for line ranges
 * Does not match: @username (no file extension or path separator)
 */
const FILE_REFERENCE_REGEX = /@((?:\.{0,2}\/)?[\w./-]+\.\w+(?::\d+(?:-\d+)?)?)/g;

/**
 * Parse a file reference to extract path and optional line range
 */
function parseReference(ref: string): { path: string; startLine?: number; endLine?: number } {
  const colonIndex = ref.lastIndexOf(":");
  // Check if colon is followed by line numbers (not part of Windows path like C:\)
  if (colonIndex > 0 && /:\d+/.test(ref.slice(colonIndex))) {
    const path = ref.slice(0, colonIndex);
    const lineSpec = ref.slice(colonIndex + 1);
    const [start, end] = lineSpec.split("-").map(Number);
    return {
      path,
      startLine: start,
      endLine: end || start, // If no end, use start (single line)
    };
  }
  return { path: ref };
}

/**
 * Read file contents, optionally limiting to a line range
 */
async function readFileContents(
  path: string,
  startLine?: number,
  endLine?: number
): Promise<string> {
  const file = Bun.file(path);

  if (!(await file.exists())) {
    throw new Error(`File not found: ${path}`);
  }

  const content = await file.text();

  // Apply line range if specified
  if (startLine !== undefined) {
    const lines = content.split("\n");
    const start = Math.max(0, startLine - 1); // Convert to 0-indexed
    const end = endLine !== undefined ? endLine : lines.length;
    return lines.slice(start, end).join("\n");
  }

  return content;
}

/**
 * Expand file references in a user message
 *
 * @param message - The user message potentially containing @file references
 * @param cwd - Current working directory for resolving relative paths
 * @returns Result with expanded message and metadata
 */
export async function expandFileReferences(
  message: string,
  cwd: string = process.cwd()
): Promise<FileReferenceResult> {
  const referencedFiles: string[] = [];
  const failedFiles: Array<{ path: string; error: string }> = [];

  // Find all file references
  const matches = [...message.matchAll(FILE_REFERENCE_REGEX)];

  if (matches.length === 0) {
    return { expandedMessage: message, referencedFiles, failedFiles };
  }

  // Build replacement map
  const replacements: Map<string, string> = new Map();

  for (const match of matches) {
    const fullMatch = match[0]; // @path/to/file.ext:1-10
    const reference = match[1]!; // path/to/file.ext:1-10

    // Skip if already processed (duplicate reference)
    if (replacements.has(fullMatch)) continue;

    const { path: filePath, startLine, endLine } = parseReference(reference);

    // Resolve path
    const absolutePath = isAbsolute(filePath) ? filePath : resolve(cwd, filePath);

    try {
      const content = await readFileContents(absolutePath, startLine, endLine);
      const lineInfo = startLine ? `:${startLine}${endLine && endLine !== startLine ? `-${endLine}` : ""}` : "";

      // Format as a code block with filename
      const replacement = `\n\n<file path="${filePath}${lineInfo}">\n${content}\n</file>\n`;

      replacements.set(fullMatch, replacement);
      referencedFiles.push(absolutePath);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : "Unknown error";
      failedFiles.push({ path: filePath, error: errorMessage });
      // Keep the original reference in the message for failed files
      replacements.set(fullMatch, `@${reference} (file not found)`);
    }
  }

  // Apply replacements
  let expandedMessage = message;
  for (const [original, replacement] of replacements) {
    expandedMessage = expandedMessage.replaceAll(original, replacement);
  }

  return { expandedMessage, referencedFiles, failedFiles };
}

