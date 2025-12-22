/**
 * Security utilities for file operations
 */

import { resolve, normalize, relative, isAbsolute } from "path";

/**
 * Validates that a given path is within the current working directory.
 * Uses canonical path resolution to prevent path traversal attacks.
 *
 * @param inputPath - The path to validate (can be relative or absolute)
 * @param basePath - The base path to validate against (defaults to cwd)
 * @throws Error if the path is outside the base directory
 * @returns The resolved absolute path if valid
 */
export function validatePathWithinBase(inputPath: string, basePath: string = process.cwd()): string {
  // Normalize and resolve both paths to canonical form
  const normalizedBase = normalize(resolve(basePath));
  const normalizedTarget = normalize(resolve(basePath, inputPath));

  // Use relative path to determine if target is within base directory.
  // This works correctly across platforms (POSIX and Windows) and avoids
  // relying on specific path separators.
  const relativePath = relative(normalizedBase, normalizedTarget);

  // If the relative path starts with ".." or is absolute, the target is
  // outside the base directory (or on a different drive on Windows).
  if (relativePath.startsWith("..") || isAbsolute(relativePath)) {
    throw new Error(`Path "${inputPath}" is outside the allowed directory`);
  }

  return normalizedTarget;
}

/**
 * Gets the relative path from base, throwing if outside base directory
 *
 * @param inputPath - The path to validate
 * @param basePath - The base path to validate against (defaults to cwd)
 * @returns Object with absolutePath and relativePath
 */
export function getSecurePaths(
  inputPath: string,
  basePath: string = process.cwd()
): { absolutePath: string; relativePath: string } {
  const absolutePath = validatePathWithinBase(inputPath, basePath);
  const normalizedBase = normalize(resolve(basePath));

  // Calculate relative path from base to target using platform-aware logic
  let relativePath = relative(normalizedBase, absolutePath);
  if (!relativePath) {
    relativePath = ".";
  }

  return { absolutePath, relativePath };
}

