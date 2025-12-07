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
      const message = error instanceof Error ? error.message : "Unknown error";
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

