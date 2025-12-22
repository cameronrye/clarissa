import { describe, test, expect } from "bun:test";
import { bashTool, isBashAvailable } from "./bash.ts";

const DEFAULT_TIMEOUT = 30000;

describe("bash tool", () => {
  describe("successful commands", () => {
    test("echo command", async () => {
      const result = await bashTool.execute({ command: "echo 'hello world'", timeout: DEFAULT_TIMEOUT });
      expect(result.success).toBe(true);
      expect(result.exitCode).toBe(0);
      expect(result.stdout).toBe("hello world");
      expect(result.stderr).toBe("");
    });

    test("pwd command", async () => {
      const result = await bashTool.execute({ command: "pwd", timeout: DEFAULT_TIMEOUT });
      expect(result.success).toBe(true);
      expect(result.exitCode).toBe(0);
      expect(result.stdout).toBeTruthy();
    });

    test("command with multiple lines output", async () => {
      const result = await bashTool.execute({ command: "echo -e 'line1\\nline2\\nline3'", timeout: DEFAULT_TIMEOUT });
      expect(result.success).toBe(true);
      expect(result.stdout).toContain("line1");
      expect(result.stdout).toContain("line2");
      expect(result.stdout).toContain("line3");
    });

    test("command with pipes", async () => {
      const result = await bashTool.execute({ command: "echo 'hello' | tr 'a-z' 'A-Z'", timeout: DEFAULT_TIMEOUT });
      expect(result.success).toBe(true);
      expect(result.stdout).toBe("HELLO");
    });
  });

  describe("failing commands", () => {
    test("command not found", async () => {
      const result = await bashTool.execute({ command: "nonexistent_command_12345", timeout: DEFAULT_TIMEOUT });
      expect(result.success).toBe(false);
      expect(result.exitCode).not.toBe(0);
    });

    test("exit with non-zero code", async () => {
      const result = await bashTool.execute({ command: "exit 1", timeout: DEFAULT_TIMEOUT });
      expect(result.success).toBe(false);
      expect(result.exitCode).toBe(1);
    });

    test("command writing to stderr", async () => {
      const result = await bashTool.execute({ command: "echo 'error' >&2", timeout: DEFAULT_TIMEOUT });
      expect(result.stderr).toBe("error");
    });
  });

  describe("timeout handling", () => {
    test("command completes before timeout", async () => {
      const result = await bashTool.execute({
        command: "echo 'fast'",
        timeout: 5000,
      });
      expect(result.success).toBe(true);
      expect(result.stdout).toBe("fast");
    });

    test("command times out", async () => {
      const result = await bashTool.execute({
        command: "sleep 10",
        timeout: 100,
      });
      expect(result.success).toBe(false);
      expect(result.stderr).toContain("timed out");
    });
  });

  describe("edge cases", () => {
    test("empty command output", async () => {
      const result = await bashTool.execute({ command: "true", timeout: DEFAULT_TIMEOUT });
      expect(result.success).toBe(true);
      expect(result.stdout).toBe("");
    });

    test("command with environment variable", async () => {
      const result = await bashTool.execute({ command: "echo $HOME", timeout: DEFAULT_TIMEOUT });
      expect(result.success).toBe(true);
      expect(result.stdout).toBeTruthy();
    });

    test("command with special characters", async () => {
      const result = await bashTool.execute({ command: "echo 'hello \"world\"'", timeout: DEFAULT_TIMEOUT });
      expect(result.success).toBe(true);
      expect(result.stdout).toBe("hello \"world\"");
    });
  });

	  describe("availability helper", () => {
	    test("isBashAvailable returns true when bash is present", async () => {
	      const available = await isBashAvailable();
	      expect(available).toBe(true);
	    });
	  });
});

