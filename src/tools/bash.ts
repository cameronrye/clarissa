import { z } from "zod";
import { defineTool } from "./base.ts";

/**
 * Dangerous command patterns that should be blocked for safety.
 * These patterns match commands that could cause severe system damage.
 */
const DANGEROUS_PATTERNS: Array<{ pattern: RegExp; reason: string }> = [
  // Recursive deletion of root, home, or current directory
  // Matches: rm -rf /, rm -rf ~, rm -rf ./, rm -rf ., etc.
  {
    pattern: /rm\s+(-[a-zA-Z]*\s+)*["']?([/~]|\.\.?\/?)["']?\s*$/i,
    reason: "Recursive deletion of root, home, or current directory",
  },
  {
    pattern: /rm\s+(-[a-zA-Z]*\s+)*["']?\/\*["']?/i,
    reason: "Recursive deletion of root contents",
  },
  // rm -rf * or rm -rf ./* (deletes everything in current directory)
  // Matches rm with -r flag (recursive) followed by wildcard
  {
    pattern: /rm\s+(-\w+\s+)*["']?\*["']?\s*$/i,
    reason: "Deletion with wildcard - potentially dangerous",
  },
  // Fork bomb patterns
  {
    pattern: /:\s*\(\s*\)\s*\{\s*:\s*\|\s*:\s*&\s*\}\s*;?\s*:/,
    reason: "Fork bomb detected",
  },
  // Overwriting boot records or critical system files
  {
    pattern: />\s*\/dev\/sd[a-z]/i,
    reason: "Writing to block device",
  },
  {
    pattern: /dd\s+.*of=\/dev\/sd[a-z]/i,
    reason: "dd to block device",
  },
  {
    pattern: /mkfs(\.\w+)?\s+.*\/dev\/sd[a-z]/i,
    reason: "Formatting block device",
  },
  // Chmod 777 on root or recursive on sensitive paths
  {
    pattern: /chmod\s+(-[a-zA-Z]*\s+)*777\s+["']?[/~]["']?\s*$/i,
    reason: "chmod 777 on root or home directory",
  },
  // Dangerous redirects that could hang the shell
  {
    pattern: />\s*\/dev\/null\s*2>&1\s*<\s*\/dev\/null/,
    reason: "Dangerous redirect pattern",
  },
  // Kill all processes
  {
    pattern: /kill\s+-9\s+-1/,
    reason: "Killing all processes",
  },
  {
    pattern: /killall\s+-9\s+/,
    reason: "Killing all processes by name",
  },
  // Prevent sudo with dangerous commands
  {
    pattern: /sudo\s+rm\s+(-[a-zA-Z]*\s+)*["']?[/~]["']?\s*$/i,
    reason: "sudo rm on root or home directory",
  },
  // Prevent overwriting /etc/passwd, /etc/shadow, etc.
  {
    pattern: />\s*\/etc\/(passwd|shadow|sudoers)/i,
    reason: "Overwriting critical system file",
  },
  // Prevent writing to /boot or /sys
  {
    pattern: />\s*\/(boot|sys)\//i,
    reason: "Writing to critical system directory",
  },
];

/**
 * Check if a command matches any dangerous patterns
 */
function isDangerousCommand(command: string): { dangerous: boolean; reason?: string } {
  const trimmed = command.trim();

  for (const { pattern, reason } of DANGEROUS_PATTERNS) {
    if (pattern.test(trimmed)) {
      return {
        dangerous: true,
        reason,
      };
    }
  }

  return { dangerous: false };
}

/**
 * Bash tool for executing shell commands
 */
export const bashTool = defineTool({
  name: "bash",
  description:
    "Execute a bash command and return the output. Use this for file operations, system commands, or running scripts. Commands are executed in the current working directory.",
  category: "system",
  requiresConfirmation: true,
  parameters: z.object({
    command: z
      .string()
      .describe("The bash command to execute"),
    timeout: z
      .number()
      .optional()
      .default(30000)
      .describe("Timeout in milliseconds (default: 30000)"),
  }),
  execute: async ({ command, timeout = 30000 }) => {
    // Check for dangerous commands before execution
    const dangerCheck = isDangerousCommand(command);
    if (dangerCheck.dangerous) {
      return {
        command,
        exitCode: -1,
        stdout: "",
        stderr: `Command blocked for safety: ${dangerCheck.reason}`,
        success: false,
      };
    }

    try {
      // Use Bun's shell for command execution
      const proc = Bun.spawn(["bash", "-c", command], {
        stdout: "pipe",
        stderr: "pipe",
        cwd: process.cwd(),
      });

      // Set up timeout with cleanup
      let timeoutId: ReturnType<typeof setTimeout> | undefined;

      const timeoutPromise = new Promise<never>((_, reject) => {
        timeoutId = setTimeout(() => {
          proc.kill();
          reject(new Error(`Command timed out after ${timeout}ms`));
        }, timeout);
      });

      try {
        // Wait for process to complete or timeout
        const exitCode = await Promise.race([proc.exited, timeoutPromise]);

        // Clear timeout since process completed
        if (timeoutId) clearTimeout(timeoutId);

        // Read stdout and stderr
        const stdout = await new Response(proc.stdout).text();
        const stderr = await new Response(proc.stderr).text();

        return {
          command,
          exitCode,
          stdout: stdout.trim(),
          stderr: stderr.trim(),
          success: exitCode === 0,
        };
      } catch (error) {
        // Clear timeout on error path too
        if (timeoutId) clearTimeout(timeoutId);
        throw error;
      }
    } catch (error) {
      let message = "Unknown error";
      if (error instanceof Error) {
        const anyErr = error as any;
        if (anyErr?.code === "ENOENT") {
          message =
            "Bash executable not found. The 'bash' tool requires 'bash' to be installed and available in your PATH.";
        } else {
          message = error.message;
        }
      }
      return {
        command,
        exitCode: -1,
        stdout: "",
        stderr: message,
        success: false,
      };
    }
  },
});

/**
 * Lightweight helper to check if the bash executable is available.
 *
 * Returns true when `bash` can be spawned, false when the executable is
 * missing (ENOENT). Other errors are treated as "available" since they
 * typically indicate runtime issues rather than a missing binary.
 */
export async function isBashAvailable(): Promise<boolean> {
  try {
    const proc = Bun.spawn(["bash", "-c", "echo"], {
      stdout: "ignore",
      stderr: "ignore",
      cwd: process.cwd(),
    });
    await proc.exited;
    return true;
  } catch (error) {
    const anyErr = error as any;
    if (anyErr?.code === "ENOENT") {
      return false;
    }
    return true;
  }
}

