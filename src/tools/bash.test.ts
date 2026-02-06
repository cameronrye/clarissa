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

  describe("dangerous command blocking", () => {
    test("blocks rm -rf /", async () => {
      const result = await bashTool.execute({ command: "rm -rf /", timeout: DEFAULT_TIMEOUT });
      expect(result.success).toBe(false);
      expect(result.stderr).toContain("blocked for safety");
    });

    test("blocks rm -rf ~", async () => {
      const result = await bashTool.execute({ command: "rm -rf ~", timeout: DEFAULT_TIMEOUT });
      expect(result.success).toBe(false);
      expect(result.stderr).toContain("blocked for safety");
    });

    test("blocks rm -rf /*", async () => {
      const result = await bashTool.execute({ command: "rm -rf /*", timeout: DEFAULT_TIMEOUT });
      expect(result.success).toBe(false);
      expect(result.stderr).toContain("blocked for safety");
    });

    test("blocks rm with wildcard", async () => {
      const result = await bashTool.execute({ command: "rm -rf *", timeout: DEFAULT_TIMEOUT });
      expect(result.success).toBe(false);
      expect(result.stderr).toContain("blocked for safety");
    });

    test("blocks fork bomb", async () => {
      const result = await bashTool.execute({ command: ":(){ :|:& };:", timeout: DEFAULT_TIMEOUT });
      expect(result.success).toBe(false);
      expect(result.stderr).toContain("blocked for safety");
    });

    test("blocks dd to block device", async () => {
      const result = await bashTool.execute({ command: "dd if=/dev/zero of=/dev/sda", timeout: DEFAULT_TIMEOUT });
      expect(result.success).toBe(false);
      expect(result.stderr).toContain("blocked for safety");
    });

    test("blocks mkfs on block device", async () => {
      const result = await bashTool.execute({ command: "mkfs.ext4 /dev/sda", timeout: DEFAULT_TIMEOUT });
      expect(result.success).toBe(false);
      expect(result.stderr).toContain("blocked for safety");
    });

    test("blocks chmod 777 on root", async () => {
      const result = await bashTool.execute({ command: "chmod -R 777 /", timeout: DEFAULT_TIMEOUT });
      expect(result.success).toBe(false);
      expect(result.stderr).toContain("blocked for safety");
    });

    test("blocks kill -9 -1", async () => {
      const result = await bashTool.execute({ command: "kill -9 -1", timeout: DEFAULT_TIMEOUT });
      expect(result.success).toBe(false);
      expect(result.stderr).toContain("blocked for safety");
    });

    test("blocks sudo rm on root", async () => {
      const result = await bashTool.execute({ command: "sudo rm -rf /", timeout: DEFAULT_TIMEOUT });
      expect(result.success).toBe(false);
      expect(result.stderr).toContain("blocked for safety");
    });

    test("blocks overwriting /etc/passwd", async () => {
      const result = await bashTool.execute({ command: "echo x > /etc/passwd", timeout: DEFAULT_TIMEOUT });
      expect(result.success).toBe(false);
      expect(result.stderr).toContain("blocked for safety");
    });

    test("blocks writing to /boot/", async () => {
      const result = await bashTool.execute({ command: "echo x > /boot/grub.cfg", timeout: DEFAULT_TIMEOUT });
      expect(result.success).toBe(false);
      expect(result.stderr).toContain("blocked for safety");
    });

    test("blocks redirect to block device", async () => {
      const result = await bashTool.execute({ command: "echo x > /dev/sda", timeout: DEFAULT_TIMEOUT });
      expect(result.success).toBe(false);
      expect(result.stderr).toContain("blocked for safety");
    });

    test("allows safe rm commands", async () => {
      // rm on a specific file should not be blocked
      const result = await bashTool.execute({ command: "rm -f /tmp/test_nonexistent_file_12345", timeout: DEFAULT_TIMEOUT });
      // Should not be blocked (may fail because file doesn't exist, but not safety-blocked)
      expect(result.stderr).not.toContain("blocked for safety");
    });

    test("allows safe echo commands", async () => {
      const result = await bashTool.execute({ command: "echo hello", timeout: DEFAULT_TIMEOUT });
      expect(result.success).toBe(true);
      expect(result.stderr).not.toContain("blocked for safety");
    });
  });

	  describe("availability helper", () => {
	    test("isBashAvailable returns true when bash is present", async () => {
	      const available = await isBashAvailable();
	      expect(available).toBe(true);
	    });
	  });
});

