import { test, expect, describe, beforeEach, afterEach } from "bun:test";
import { listDirectoryTool } from "./file-list.ts";
import { searchFilesTool } from "./file-search.ts";
import { rm, mkdir } from "fs/promises";
import { join } from "path";

const TEST_DIR = "test-fixtures-list";

describe("Directory Listing", () => {
  beforeEach(async () => {
    await mkdir(join(TEST_DIR, "subdir"), { recursive: true });
    await Bun.write(join(TEST_DIR, "file1.ts"), "content 1");
    await Bun.write(join(TEST_DIR, "file2.ts"), "content 2");
    await Bun.write(join(TEST_DIR, "subdir/nested.ts"), "nested content");
    await Bun.write(join(TEST_DIR, ".hidden"), "hidden file");
  });

  afterEach(async () => {
    await rm(TEST_DIR, { recursive: true, force: true });
  });

  describe("list_directory", () => {
    test("lists files and directories", async () => {
      const result = await listDirectoryTool.execute({ path: TEST_DIR, depth: 2, showHidden: false });
      expect(result.tree).toContain("file1.ts");
      expect(result.tree).toContain("file2.ts");
      expect(result.tree).toContain("subdir/");
    });

    test("shows nested files with depth", async () => {
      const result = await listDirectoryTool.execute({ path: TEST_DIR, depth: 2, showHidden: false });
      expect(result.tree).toContain("nested.ts");
    });

    test("hides hidden files by default", async () => {
      const result = await listDirectoryTool.execute({ path: TEST_DIR, depth: 2, showHidden: false });
      expect(result.tree).not.toContain(".hidden");
    });

    test("shows hidden files when enabled", async () => {
      const result = await listDirectoryTool.execute({ path: TEST_DIR, depth: 2, showHidden: true });
      expect(result.tree).toContain(".hidden");
    });

    test("respects depth limit", async () => {
      const result = await listDirectoryTool.execute({ path: TEST_DIR, depth: 1, showHidden: false });
      expect(result.tree).toContain("subdir/");
      expect(result.tree).not.toContain("nested.ts");
    });

    test("throws error for path outside cwd", async () => {
      expect(listDirectoryTool.execute({ path: "../../../etc", depth: 2, showHidden: false }))
        .rejects.toThrow("outside the allowed directory");
    });
  });
});

describe("File Search", () => {
  beforeEach(async () => {
    await mkdir(join(TEST_DIR, "subdir"), { recursive: true });
    await Bun.write(join(TEST_DIR, "main.ts"), "const greeting = 'Hello World';\nexport function greet() {}");
    await Bun.write(join(TEST_DIR, "helper.ts"), "function helper() { return 'Hello'; }");
    await Bun.write(join(TEST_DIR, "styles.css"), ".hello { color: red; }");
    await Bun.write(join(TEST_DIR, "subdir/nested.ts"), "const nested = 'Hello Nested';");
  });

  afterEach(async () => {
    await rm(TEST_DIR, { recursive: true, force: true });
  });

  describe("search_files", () => {
    test("finds pattern matches across files", async () => {
      const result = await searchFilesTool.execute({
        pattern: "Hello",
        path: TEST_DIR,
        maxResults: 20,
        caseSensitive: false,
      });
      expect(result.matchCount).toBeGreaterThan(0);
      expect(result.matches).toContain("Hello");
    });

    test("searches recursively", async () => {
      const result = await searchFilesTool.execute({
        pattern: "nested",
        path: TEST_DIR,
        maxResults: 20,
        caseSensitive: false,
      });
      expect(result.matches).toContain("nested.ts");
    });

    test("filters by file pattern", async () => {
      const result = await searchFilesTool.execute({
        pattern: "hello",
        path: TEST_DIR,
        maxResults: 20,
        caseSensitive: false,
        filePattern: "*.ts",
      });
      expect(result.matches).not.toContain("styles.css");
    });

    test("respects case sensitivity", async () => {
      const resultInsensitive = await searchFilesTool.execute({
        pattern: "hello",
        path: TEST_DIR,
        maxResults: 20,
        caseSensitive: false,
      });
      const resultSensitive = await searchFilesTool.execute({
        pattern: "hello",
        path: TEST_DIR,
        maxResults: 20,
        caseSensitive: true,
      });
      expect(resultInsensitive.matchCount).toBeGreaterThan(resultSensitive.matchCount);
    });

    test("respects maxResults", async () => {
      const result = await searchFilesTool.execute({
        pattern: "Hello",
        path: TEST_DIR,
        maxResults: 2,
        caseSensitive: false,
      });
      expect(result.matchCount).toBeLessThanOrEqual(2);
      expect(result.truncated).toBe(true);
    });

    test("throws error for path outside cwd", async () => {
      expect(searchFilesTool.execute({ pattern: "test", path: "../../../etc", maxResults: 20, caseSensitive: false }))
        .rejects.toThrow("outside the allowed directory");
    });
  });
});

