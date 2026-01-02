import { test, expect, describe, beforeAll, afterAll } from "bun:test";
import { expandFileReferences } from "./file-references.ts";
import { join } from "path";
import { rm, mkdir } from "fs/promises";

const TEST_DIR = join(import.meta.dir, "__test_files__");

describe("File References", () => {
  beforeAll(async () => {
    await mkdir(TEST_DIR, { recursive: true });
    await Bun.write(join(TEST_DIR, "test.txt"), "line 1\nline 2\nline 3\nline 4\nline 5");
    await Bun.write(join(TEST_DIR, "code.ts"), "const x = 1;\nconst y = 2;\nexport { x, y };");
    await Bun.write(join(TEST_DIR, "sub/nested.md"), "# Nested\n\nContent here.");
  });

  afterAll(async () => {
    await rm(TEST_DIR, { recursive: true, force: true });
  });

  describe("expandFileReferences", () => {
    test("returns unchanged message when no references", async () => {
      const result = await expandFileReferences("Hello world", TEST_DIR);
      expect(result.expandedMessage).toBe("Hello world");
      expect(result.referencedFiles).toHaveLength(0);
      expect(result.failedFiles).toHaveLength(0);
    });

    test("does not match @username patterns", async () => {
      const result = await expandFileReferences("Hello @user how are you?", TEST_DIR);
      expect(result.expandedMessage).toBe("Hello @user how are you?");
      expect(result.referencedFiles).toHaveLength(0);
    });

    test("expands simple file reference", async () => {
      const result = await expandFileReferences("Check @test.txt please", TEST_DIR);
      expect(result.expandedMessage).toContain('<file path="test.txt">');
      expect(result.expandedMessage).toContain("line 1\nline 2\nline 3");
      expect(result.referencedFiles).toHaveLength(1);
      expect(result.referencedFiles[0]).toContain("test.txt");
    });

    test("expands file reference with extension", async () => {
      const result = await expandFileReferences("Look at @code.ts", TEST_DIR);
      expect(result.expandedMessage).toContain('<file path="code.ts">');
      expect(result.expandedMessage).toContain("const x = 1;");
      expect(result.referencedFiles).toHaveLength(1);
    });

    test("expands relative path with ./", async () => {
      const result = await expandFileReferences("See @./test.txt", TEST_DIR);
      expect(result.expandedMessage).toContain('<file path="./test.txt">');
      expect(result.referencedFiles).toHaveLength(1);
    });

    test("expands nested path", async () => {
      const result = await expandFileReferences("Read @sub/nested.md", TEST_DIR);
      expect(result.expandedMessage).toContain('<file path="sub/nested.md">');
      expect(result.expandedMessage).toContain("# Nested");
      expect(result.referencedFiles).toHaveLength(1);
    });

    test("handles line range - single line", async () => {
      const result = await expandFileReferences("Line @test.txt:2", TEST_DIR);
      expect(result.expandedMessage).toContain('<file path="test.txt:2">');
      expect(result.expandedMessage).toContain("line 2");
      expect(result.expandedMessage).not.toContain("line 1");
      expect(result.expandedMessage).not.toContain("line 3");
    });

    test("handles line range - multiple lines", async () => {
      const result = await expandFileReferences("Lines @test.txt:2-4", TEST_DIR);
      expect(result.expandedMessage).toContain('<file path="test.txt:2-4">');
      expect(result.expandedMessage).toContain("line 2");
      expect(result.expandedMessage).toContain("line 3");
      expect(result.expandedMessage).toContain("line 4");
      expect(result.expandedMessage).not.toContain("line 1");
      expect(result.expandedMessage).not.toContain("line 5");
    });

    test("handles multiple file references", async () => {
      const result = await expandFileReferences("Compare @test.txt with @code.ts", TEST_DIR);
      expect(result.expandedMessage).toContain('<file path="test.txt">');
      expect(result.expandedMessage).toContain('<file path="code.ts">');
      expect(result.referencedFiles).toHaveLength(2);
    });

    test("handles missing file gracefully", async () => {
      const result = await expandFileReferences("Check @nonexistent.txt", TEST_DIR);
      expect(result.expandedMessage).toContain("@nonexistent.txt (file not found)");
      expect(result.referencedFiles).toHaveLength(0);
      expect(result.failedFiles).toHaveLength(1);
      expect(result.failedFiles[0]?.path).toBe("nonexistent.txt");
    });

    test("handles duplicate references", async () => {
      const result = await expandFileReferences("@test.txt and also @test.txt", TEST_DIR);
      // Both occurrences should be replaced
      expect(result.expandedMessage).not.toContain("@test.txt");
      // But only one file in the list
      expect(result.referencedFiles).toHaveLength(1);
    });
  });
});

