import { z } from "zod";
import { defineTool } from "./base.ts";

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

