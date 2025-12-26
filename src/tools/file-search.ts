import { z } from "zod";
import { defineTool } from "./base.ts";
import { relative, join } from "path";
import { readdir, stat } from "fs/promises";
import { getSecurePaths } from "./security.ts";

interface SearchMatch {
  file: string;
  line: number;
  content: string;
}

/**
 * Maximum allowed regex pattern length to prevent ReDoS attacks
 */
const MAX_PATTERN_LENGTH = 500;

/**
 * Patterns that are known to be vulnerable to ReDoS
 * These check for common catastrophic backtracking patterns
 */
const DANGEROUS_REGEX_PATTERNS = [
  // Nested quantifiers like (a+)+ or (a*)*
  /\([^)]*[+*][^)]*\)[+*]/,
  // Overlapping alternations with quantifiers
  /\([^|)]+\|[^|)]+\)[+*]/,
];

/**
 * Validate regex pattern for potential ReDoS vulnerabilities
 */
function validateRegexPattern(pattern: string): { valid: boolean; reason?: string } {
  if (pattern.length > MAX_PATTERN_LENGTH) {
    return { valid: false, reason: `Pattern too long (max ${MAX_PATTERN_LENGTH} characters)` };
  }

  for (const dangerous of DANGEROUS_REGEX_PATTERNS) {
    if (dangerous.test(pattern)) {
      return { valid: false, reason: "Pattern contains potentially dangerous nested quantifiers" };
    }
  }

  // Try to compile the regex to catch syntax errors early
  try {
    new RegExp(pattern);
  } catch (error) {
    const msg = error instanceof Error ? error.message : "Invalid regex";
    return { valid: false, reason: msg };
  }

  return { valid: true };
}

/**
 * Search files tool - grep-like regex search
 */
export const searchFilesTool = defineTool({
  name: "search_files",
  description:
    "Search for a pattern across files in a directory. Returns matching lines with file paths and line numbers. Like grep but for the project.",
  parameters: z.object({
    pattern: z.string().describe("Regex pattern to search for"),
    path: z
      .string()
      .optional()
      .default(".")
      .describe("Directory to search in (default: current directory)"),
    filePattern: z
      .string()
      .optional()
      .describe("Glob pattern to filter files (e.g., '*.ts', '*.tsx')"),
    maxResults: z
      .number()
      .int()
      .min(1)
      .max(100)
      .optional()
      .default(20)
      .describe("Maximum results to return (default: 20)"),
    caseSensitive: z
      .boolean()
      .optional()
      .default(false)
      .describe("Case-sensitive search (default: false)"),
  }),
  execute: async ({ pattern, path = ".", filePattern, maxResults = 20, caseSensitive = false }) => {
    try {
      // Validate regex pattern to prevent ReDoS attacks
      const patternValidation = validateRegexPattern(pattern);
      if (!patternValidation.valid) {
        throw new Error(`Invalid search pattern: ${patternValidation.reason}`);
      }

      // Security check with canonical path resolution
      const { absolutePath, relativePath } = getSecurePaths(path);

      // Use non-global regex for testing (global flag causes lastIndex issues with .test())
      const regex = new RegExp(pattern, caseSensitive ? "" : "i");
      const matches: SearchMatch[] = [];
      const ignoredDirs = new Set(["node_modules", ".git", "dist", "build", ".next", "__pycache__", "bun.lock"]);
      const binaryExtensions = new Set([".png", ".jpg", ".jpeg", ".gif", ".ico", ".woff", ".woff2", ".ttf", ".eot"]);

      // Convert glob to regex for file filtering
      let fileRegex: RegExp | null = null;
      if (filePattern) {
        const regexPattern = filePattern
          .replace(/\./g, "\\.")
          .replace(/\*/g, ".*")
          .replace(/\?/g, ".");
        fileRegex = new RegExp(`^${regexPattern}$`);
      }

      async function searchDir(dirPath: string): Promise<void> {
        if (matches.length >= maxResults) return;

        let items: string[];
        try {
          items = await readdir(dirPath);
        } catch {
          return;
        }

        for (const item of items) {
          if (matches.length >= maxResults) break;
          if (item.startsWith(".") || ignoredDirs.has(item)) continue;

          const itemPath = join(dirPath, item);

          try {
            const stats = await stat(itemPath);

            if (stats.isDirectory()) {
              await searchDir(itemPath);
            } else if (stats.isFile()) {
              // Check file pattern
              if (fileRegex && !fileRegex.test(item)) continue;

              // Skip binary files
              const ext = item.substring(item.lastIndexOf(".")).toLowerCase();
              if (binaryExtensions.has(ext)) continue;

              // Skip large files
              if (stats.size > 1024 * 1024) continue;

              const file = Bun.file(itemPath);
              const content = await file.text();
              const lines = content.split("\n");

              for (let i = 0; i < lines.length && matches.length < maxResults; i++) {
                const line = lines[i];
                if (line && regex.test(line)) {
                  matches.push({
                    file: relative(process.cwd(), itemPath),
                    line: i + 1,
                    content: line.trim().substring(0, 200),
                  });
                }
              }
            }
          } catch {
            continue;
          }
        }
      }

      await searchDir(absolutePath);

      return {
        pattern,
        path: relativePath,
        matchCount: matches.length,
        truncated: matches.length >= maxResults,
        matches: matches.map((m) => `${m.file}:${m.line}: ${m.content}`).join("\n"),
      };
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unknown error";
      throw new Error(`Failed to search files: ${message}`);
    }
  },
});

