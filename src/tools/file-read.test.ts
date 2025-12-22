import { test, expect, describe, beforeEach, afterEach } from "bun:test";
import { readFileTool } from "./file-read.ts";
import { writeFileTool } from "./file-write.ts";
import { patchFileTool } from "./file-patch.ts";
import { rm, mkdir } from "fs/promises";
import { join } from "path";

const TEST_DIR = "test-fixtures";

describe("File Operations", () => {
  beforeEach(async () => {
    await mkdir(TEST_DIR, { recursive: true });
    await Bun.write(join(TEST_DIR, "sample.txt"), "line 1\nline 2\nline 3\nline 4\nline 5");
    await Bun.write(join(TEST_DIR, "test.ts"), "const x = 1;\nconst y = 2;\nfunction add() { return x + y; }");
  });

  afterEach(async () => {
    await rm(TEST_DIR, { recursive: true, force: true });
  });

  describe("read_file", () => {
    test("reads entire file with line numbers", async () => {
      const result = await readFileTool.execute({ path: join(TEST_DIR, "sample.txt") });
      expect(result.content).toContain("1 | line 1");
      expect(result.content).toContain("5 | line 5");
      expect(result.totalLines).toBe(5);
    });

    test("reads specific line range", async () => {
      const result = await readFileTool.execute({
        path: join(TEST_DIR, "sample.txt"),
        startLine: 2,
        endLine: 4,
      });
      expect(result.content).toContain("2 | line 2");
      expect(result.content).toContain("4 | line 4");
      expect(result.content).not.toContain("1 | line 1");
      expect(result.content).not.toContain("5 | line 5");
    });

    test("reads from start to end of file with -1", async () => {
      const result = await readFileTool.execute({
        path: join(TEST_DIR, "sample.txt"),
        startLine: 3,
        endLine: -1,
      });
      expect(result.content).toContain("3 | line 3");
      expect(result.content).toContain("5 | line 5");
      expect(result.content).not.toContain("1 | line 1");
    });

    test("throws error for non-existent file", async () => {
      expect(readFileTool.execute({ path: join(TEST_DIR, "nonexistent.txt") }))
        .rejects.toThrow("File not found");
    });

    test("throws error for path outside cwd", async () => {
      expect(readFileTool.execute({ path: "../../../etc/passwd" }))
        .rejects.toThrow("outside the allowed directory");
    });

    test("throws error for start line exceeding file length", async () => {
      expect(readFileTool.execute({ path: join(TEST_DIR, "sample.txt"), startLine: 100 }))
        .rejects.toThrow("exceeds file length");
    });

    test("allows endLine = -1 through parameter schema", () => {
      const parsed = readFileTool.parameters.parse({
        path: join(TEST_DIR, "sample.txt"),
        startLine: 3,
        endLine: -1,
      });

      expect(parsed.endLine).toBe(-1);
    });

    test("rejects invalid endLine values through parameter schema", () => {
      expect(() =>
        readFileTool.parameters.parse({
          path: join(TEST_DIR, "sample.txt"),
          endLine: 0,
        }),
      ).toThrow("endLine must be a positive integer or -1 for end of file");
    });
  });

  describe("write_file", () => {
    test("creates new file", async () => {
      const result = await writeFileTool.execute({
        path: join(TEST_DIR, "new-file.txt"),
        content: "hello world",
      });
      expect(result.action).toBe("created");
      expect(result.lines).toBe(1);
      
      const content = await Bun.file(join(TEST_DIR, "new-file.txt")).text();
      expect(content).toBe("hello world");
    });

    test("updates existing file", async () => {
      const result = await writeFileTool.execute({
        path: join(TEST_DIR, "sample.txt"),
        content: "updated content",
      });
      expect(result.action).toBe("updated");
    });

    test("creates parent directories", async () => {
      const result = await writeFileTool.execute({
        path: join(TEST_DIR, "nested/deep/file.txt"),
        content: "nested content",
      });
      expect(result.action).toBe("created");
      
      const content = await Bun.file(join(TEST_DIR, "nested/deep/file.txt")).text();
      expect(content).toBe("nested content");
    });

    test("throws error for path outside cwd", async () => {
      expect(writeFileTool.execute({ path: "../../../tmp/test.txt", content: "test" }))
        .rejects.toThrow("outside the allowed directory");
    });
  });

  describe("patch_file", () => {
    test("replaces exact string match", async () => {
      const result = await patchFileTool.execute({
        path: join(TEST_DIR, "sample.txt"),
        oldStr: "line 2",
        newStr: "modified line 2",
      });
      expect(result.linesRemoved).toBe(1);
      expect(result.linesAdded).toBe(1);
      
      const content = await Bun.file(join(TEST_DIR, "sample.txt")).text();
      expect(content).toContain("modified line 2");
    });

    test("deletes content when newStr is empty", async () => {
      const result = await patchFileTool.execute({
        path: join(TEST_DIR, "sample.txt"),
        oldStr: "line 3\n",
        newStr: "",
      });
      expect(result.linesRemoved).toBe(2);
      expect(result.linesAdded).toBe(1);
    });

    test("throws error when string not found", async () => {
      expect(patchFileTool.execute({
        path: join(TEST_DIR, "sample.txt"),
        oldStr: "nonexistent text",
        newStr: "replacement",
      })).rejects.toThrow("String not found");
    });

    test("throws error for multiple occurrences", async () => {
      await Bun.write(join(TEST_DIR, "duplicate.txt"), "word word word");
      expect(patchFileTool.execute({
        path: join(TEST_DIR, "duplicate.txt"),
        oldStr: "word",
        newStr: "changed",
      })).rejects.toThrow("occurrences");
    });
  });
});

