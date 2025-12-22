import { test, expect, describe, beforeEach, afterEach } from "bun:test";
import {
	  gitStatusTool,
	  gitDiffTool,
	  gitLogTool,
	  gitAddTool,
	  gitBranchTool,
	  isGitAvailable,
	} from "./git.ts";
import { rm, mkdir } from "fs/promises";

const TEST_DIR = "test-git-repo";

describe("Git Tools", () => {
  const originalCwd = process.cwd();

  beforeEach(async () => {
    await mkdir(TEST_DIR, { recursive: true });
    process.chdir(TEST_DIR);
    
    // Initialize a git repo for testing
    await Bun.spawn(["git", "init"], { cwd: process.cwd() }).exited;
    await Bun.spawn(["git", "config", "user.email", "test@test.com"], { cwd: process.cwd() }).exited;
    await Bun.spawn(["git", "config", "user.name", "Test User"], { cwd: process.cwd() }).exited;
    
    // Create initial commit
    await Bun.write("initial.txt", "initial content");
    await Bun.spawn(["git", "add", "."], { cwd: process.cwd() }).exited;
    await Bun.spawn(["git", "commit", "-m", "Initial commit"], { cwd: process.cwd() }).exited;
  });

  afterEach(async () => {
    process.chdir(originalCwd);
    await rm(TEST_DIR, { recursive: true, force: true });
  });

  describe("git_status", () => {
    test("shows clean working tree", async () => {
      const result = await gitStatusTool.execute({ short: false });
      expect(result.status).toContain("nothing to commit");
    });

    test("shows modified files", async () => {
      await Bun.write("initial.txt", "modified content");
      const result = await gitStatusTool.execute({ short: false });
      expect(result.status).toContain("modified");
    });

    test("shows short format", async () => {
      await Bun.write("new-file.txt", "new content");
      const result = await gitStatusTool.execute({ short: true });
      expect(result.status).toContain("??");
    });

    test("shows untracked files", async () => {
      await Bun.write("untracked.txt", "untracked content");
      const result = await gitStatusTool.execute({ short: false });
      expect(result.status).toContain("untracked.txt");
    });
  });

  describe("git_diff", () => {
    test("shows no changes when clean", async () => {
      const result = await gitDiffTool.execute({ staged: false });
      expect(result.diff).toBe("No changes");
    });

    test("shows unstaged changes", async () => {
      await Bun.write("initial.txt", "modified content");
      const result = await gitDiffTool.execute({ staged: false });
      expect(result.diff).toContain("modified content");
    });

    test("shows staged changes", async () => {
      await Bun.write("initial.txt", "staged content");
      await Bun.spawn(["git", "add", "initial.txt"], { cwd: process.cwd() }).exited;
      const result = await gitDiffTool.execute({ staged: true });
      expect(result.diff).toContain("staged content");
    });

    test("diffs specific file", async () => {
      await Bun.write("initial.txt", "changed");
      await Bun.write("other.txt", "other changes");
      const result = await gitDiffTool.execute({ staged: false, file: "initial.txt" });
      expect(result.diff).toContain("changed");
      expect(result.diff).not.toContain("other changes");
    });
  });

  describe("git_log", () => {
    test("shows commit history", async () => {
      const result = await gitLogTool.execute({ count: 10, oneline: true });
      expect(result.log).toContain("Initial commit");
    });

    test("respects count parameter", async () => {
      await Bun.write("second.txt", "second");
      await Bun.spawn(["git", "add", "."], { cwd: process.cwd() }).exited;
      await Bun.spawn(["git", "commit", "-m", "Second commit"], { cwd: process.cwd() }).exited;

      const result = await gitLogTool.execute({ count: 1, oneline: true });
      expect(result.log).toContain("Second commit");
      expect(result.log).not.toContain("Initial commit");
    });

    test("shows file-specific history", async () => {
      const result = await gitLogTool.execute({ count: 10, oneline: true, file: "initial.txt" });
      expect(result.log).toContain("Initial commit");
    });
  });

  describe("git_add", () => {
    test("stages files", async () => {
      await Bun.write("new-file.txt", "new content");
      const result = await gitAddTool.execute({ files: ["new-file.txt"] });
      expect(result.message).toContain("Staged");

      const status = await gitStatusTool.execute({ short: true });
      expect(status.status).toContain("A");
    });

    test("stages all files with '.'", async () => {
      await Bun.write("file1.txt", "content1");
      await Bun.write("file2.txt", "content2");
      const result = await gitAddTool.execute({ files: ["."] });
      expect(result.message).toContain("Staged");
    });
  });

  describe("git_branch", () => {
    test("lists branches", async () => {
      const result = await gitBranchTool.execute({ action: "list" });
      expect(result.output).toBeDefined();
    });

    test("creates new branch", async () => {
      const result = await gitBranchTool.execute({ action: "create", name: "feature-branch" });
      expect(result.output).toContain("successful");

      const branches = await gitBranchTool.execute({ action: "list" });
      expect(branches.output).toContain("feature-branch");
    });
  });

	  describe("availability helper", () => {
	    test("isGitAvailable returns true when git is present", async () => {
	      const available = await isGitAvailable();
	      expect(available).toBe(true);
	    });
	  });
});

