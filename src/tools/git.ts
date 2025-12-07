import { z } from "zod";
import { defineTool } from "./base.ts";

/**
 * Helper to execute git commands
 */
async function execGit(args: string[]): Promise<{ stdout: string; stderr: string; exitCode: number }> {
  const proc = Bun.spawn(["git", ...args], {
    stdout: "pipe",
    stderr: "pipe",
    cwd: process.cwd(),
  });

  const exitCode = await proc.exited;
  const stdout = await new Response(proc.stdout).text();
  const stderr = await new Response(proc.stderr).text();

  return { stdout: stdout.trim(), stderr: stderr.trim(), exitCode };
}

/**
 * Git status tool
 */
export const gitStatusTool = defineTool({
  name: "git_status",
  description: "Show the working tree status. Lists staged, unstaged, and untracked files.",
  parameters: z.object({
    short: z.boolean().optional().default(false).describe("Use short format output"),
  }),
  execute: async ({ short }) => {
    const args = ["status"];
    if (short) args.push("--short");

    const { stdout, stderr, exitCode } = await execGit(args);
    if (exitCode !== 0) throw new Error(stderr || "Git status failed");

    return { status: stdout || "Nothing to commit, working tree clean" };
  },
});

/**
 * Git diff tool
 */
export const gitDiffTool = defineTool({
  name: "git_diff",
  description: "Show changes between commits, commit and working tree, etc.",
  parameters: z.object({
    staged: z.boolean().optional().default(false).describe("Show staged changes (--cached)"),
    file: z.string().optional().describe("Specific file to diff"),
  }),
  execute: async ({ staged, file }) => {
    const args = ["diff"];
    if (staged) args.push("--cached");
    if (file) args.push("--", file);

    const { stdout, stderr, exitCode } = await execGit(args);
    if (exitCode !== 0) throw new Error(stderr || "Git diff failed");

    return { diff: stdout || "No changes" };
  },
});

/**
 * Git log tool
 */
export const gitLogTool = defineTool({
  name: "git_log",
  description: "Show commit history.",
  parameters: z.object({
    count: z.number().int().min(1).max(50).optional().default(10).describe("Number of commits to show"),
    oneline: z.boolean().optional().default(true).describe("Compact one-line format"),
    file: z.string().optional().describe("Show commits for a specific file"),
  }),
  execute: async ({ count, oneline, file }) => {
    const args = ["log", `-${count}`];
    if (oneline) args.push("--oneline");
    if (file) args.push("--", file);

    const { stdout, stderr, exitCode } = await execGit(args);
    if (exitCode !== 0) throw new Error(stderr || "Git log failed");

    return { log: stdout || "No commits yet" };
  },
});

/**
 * Git add tool
 */
export const gitAddTool = defineTool({
  name: "git_add",
  description: "Stage files for commit.",
  category: "git",
  requiresConfirmation: true,
  parameters: z.object({
    files: z.array(z.string()).describe("Files to stage (use ['.'] for all)"),
  }),
  execute: async ({ files }) => {
    const { stdout, stderr, exitCode } = await execGit(["add", ...files]);
    if (exitCode !== 0) throw new Error(stderr || "Git add failed");

    return { message: `Staged: ${files.join(", ")}`, output: stdout };
  },
});

/**
 * Git commit tool
 */
export const gitCommitTool = defineTool({
  name: "git_commit",
  description: "Record changes to the repository.",
  category: "git",
  requiresConfirmation: true,
  parameters: z.object({
    message: z.string().describe("Commit message"),
    all: z.boolean().optional().default(false).describe("Automatically stage modified files (-a)"),
  }),
  execute: async ({ message, all }) => {
    const args = ["commit", "-m", message];
    if (all) args.splice(1, 0, "-a");

    const { stdout, stderr, exitCode } = await execGit(args);
    if (exitCode !== 0) throw new Error(stderr || "Git commit failed");

    return { message: "Committed successfully", output: stdout };
  },
});

/**
 * Git branch tool
 */
export const gitBranchTool = defineTool({
  name: "git_branch",
  description: "List, create, or switch branches.",
  parameters: z.object({
    action: z.enum(["list", "create", "switch"]).describe("Action to perform"),
    name: z.string().optional().describe("Branch name (required for create/switch)"),
  }),
  execute: async ({ action, name }) => {
    if ((action === "create" || action === "switch") && !name) {
      throw new Error(`Branch name required for ${action}`);
    }

    let args: string[];
    switch (action) {
      case "list":
        args = ["branch", "-a"];
        break;
      case "create":
        args = ["branch", name!];
        break;
      case "switch":
        args = ["checkout", name!];
        break;
    }

    const { stdout, stderr, exitCode } = await execGit(args);
    if (exitCode !== 0) throw new Error(stderr || `Git ${action} failed`);

    return { output: stdout || `Branch ${action} successful` };
  },
});

