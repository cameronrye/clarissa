import { llmClient } from "./llm/client.ts";
import { toolRegistry } from "./tools/index.ts";
import { agentConfig } from "./config/index.ts";
import { contextManager } from "./llm/context.ts";
import { memoryManager } from "./memory/index.ts";
import { expandFileReferences } from "./context/index.ts";
import type { Message, ToolResult } from "./llm/types.ts";

export interface AgentCallbacks {
  onThinking?: () => void;
  onToolCall?: (name: string, args: string) => void;
  onToolConfirmation?: (name: string, args: string) => Promise<boolean>;
  onToolResult?: (name: string, result: string) => void;
  onResponse?: (content: string) => void;
  onStreamChunk?: (chunk: string) => void;
  onError?: (error: Error) => void;
}

/**
 * Build the base system prompt with the given tool names
 * Includes explicit tool usage guidelines (iOS pattern from Apple Foundation Models best practices)
 */
function buildBaseSystemPrompt(toolNames: string[]): string {
  // Build tool-specific guidance based on available tools
  const toolGuidance: string[] = [];

  if (toolNames.includes("calculator")) {
    toolGuidance.push("- For math calculations, use the calculator tool");
  }
  if (toolNames.includes("bash")) {
    toolGuidance.push("- For shell commands and system operations, use the bash tool");
  }
  if (toolNames.includes("read_file")) {
    toolGuidance.push("- To read file contents, use the read_file tool");
  }
  if (toolNames.includes("write_file")) {
    toolGuidance.push("- To create or overwrite files, use the write_file tool");
  }
  if (toolNames.includes("patch_file")) {
    toolGuidance.push("- To edit existing files, prefer the patch_file tool");
  }
  if (toolNames.includes("list_directory")) {
    toolGuidance.push("- To list directory contents, use the list_directory tool");
  }
  if (toolNames.includes("search_files")) {
    toolGuidance.push("- To search for patterns in files, use the search_files tool");
  }
  if (toolNames.includes("git_status") || toolNames.includes("git_diff")) {
    toolGuidance.push("- For git operations, use the appropriate git_* tools");
  }
  if (toolNames.includes("web_fetch")) {
    toolGuidance.push("- To fetch web content, use the web_fetch tool");
  }

  const toolGuidanceText = toolGuidance.length > 0
    ? `\n\nTool usage guidelines:\n${toolGuidance.join("\n")}`
    : "";

  return `You are Clarissa, a helpful AI assistant with access to tools.

You can use the following tools:
${toolNames.map((name) => `- ${name}`).join("\n")}
${toolGuidanceText}

When you need to perform calculations, run commands, or interact with the system, use the appropriate tool.
Always explain what you're doing and provide clear, helpful responses.
If a tool fails, explain the error and suggest alternatives if possible.

Be concise but thorough. Format your responses for terminal display using plain text.
Do not use LaTeX notation like \\( \\) or \\[ \\]. Write math expressions in plain text (e.g., "9 * 8 - 72 = 0").`;
}

/**
 * Build the full system prompt including memories
 */
async function buildSystemPrompt(toolNames: string[]): Promise<string> {
  const basePrompt = buildBaseSystemPrompt(toolNames);
  const memories = await memoryManager.getForPrompt();
  if (memories) {
    return `${basePrompt}\n\n${memories}`;
  }
  return basePrompt;
}

/**
 * The Clarissa Agent - implements the ReAct loop pattern
 */
export class Agent {
  private messages: Message[] = [];
  private callbacks: AgentCallbacks;
  private cachedSystemPrompt: string | null = null;
  private cachedMemoryVersion = -1;
  private cachedToolNames: string[] = [];
  private abortController: AbortController | null = null;

  constructor(callbacks: AgentCallbacks = {}) {
    this.callbacks = callbacks;
    // System prompt will be initialized on first run with correct tool names
  }

  /**
   * Abort the currently running agent loop.
   * Safe to call even if no run is in progress.
   */
  abort(): void {
    this.abortController?.abort();
  }

  /**
   * Update the system prompt with current memories and tool names (cached)
   */
  private async updateSystemPrompt(toolNames: string[]): Promise<void> {
    const currentVersion = memoryManager.getVersion();
    const toolNamesChanged = JSON.stringify(toolNames) !== JSON.stringify(this.cachedToolNames);

    // Only rebuild if memories or tool names have changed
    if (this.cachedSystemPrompt === null || this.cachedMemoryVersion !== currentVersion || toolNamesChanged) {
      this.cachedSystemPrompt = await buildSystemPrompt(toolNames);
      this.cachedMemoryVersion = currentVersion;
      this.cachedToolNames = toolNames;
    }

    // Update or add system message
    if (this.messages[0] && this.messages[0].role === "system") {
      this.messages[0].content = this.cachedSystemPrompt;
    } else {
      this.messages.unshift({
        role: "system",
        content: this.cachedSystemPrompt,
      });
    }
  }

  /**
   * Run the agent with a user message
   */
  async run(userMessage: string): Promise<string> {
    // Create a new AbortController for this run
    this.abortController = new AbortController();
    const { signal } = this.abortController;

    // Get provider's max tools capability and select appropriate tool set
    // Do this FIRST so we can build the system prompt with correct tool names
    const maxTools = await llmClient.getMaxTools();
    const tools = toolRegistry.getDefinitionsLimited(maxTools);
    const toolNames = tools.map(t => t.function.name);

    // Update system prompt with current memories and tool names
    await this.updateSystemPrompt(toolNames);

    // Expand file references (@filename syntax) in the user message
    const { expandedMessage, referencedFiles, failedFiles } = await expandFileReferences(userMessage);

    // Log file reference results if any
    if (referencedFiles.length > 0 || failedFiles.length > 0) {
      if (process.env.DEBUG) {
        console.log(`[File References] Loaded: ${referencedFiles.length}, Failed: ${failedFiles.length}`);
        if (failedFiles.length > 0) {
          for (const { path, error } of failedFiles) {
            console.log(`  - ${path}: ${error}`);
          }
        }
      }
    }

    // Add user message with expanded file contents
    this.messages.push({
      role: "user",
      content: expandedMessage,
    });

    // Truncate context if needed
    this.messages = contextManager.truncateToFit(this.messages);

    // Run the agent loop
    for (let i = 0; i < agentConfig.maxIterations; i++) {
      // Check if the run was aborted
      if (signal.aborted) {
        return "Request cancelled.";
      }

      this.callbacks.onThinking?.();

      // Get LLM response with streaming
      const response = await llmClient.chatStreamComplete(
        this.messages,
        tools,
        agentConfig.model,
        this.callbacks.onStreamChunk
      );

      // Add assistant message to history
      this.messages.push(response);

      // Check if there are tool calls
      if (response.tool_calls && response.tool_calls.length > 0) {
        // Separate tool calls into those needing confirmation and those that don't.
        // Confirmation tools must run sequentially (user confirms one at a time),
        // but auto-approved tools can run in parallel for better performance.
        const needsConfirmation: typeof response.tool_calls = [];
        const autoApproved: typeof response.tool_calls = [];

        for (const toolCall of response.tool_calls) {
          const { name } = toolCall.function;
          if (!agentConfig.autoApprove && toolRegistry.requiresConfirmation(name) && this.callbacks.onToolConfirmation) {
            needsConfirmation.push(toolCall);
          } else {
            autoApproved.push(toolCall);
          }
        }

        const toolResults: ToolResult[] = [];

        // Check abort before executing tools
        if (signal.aborted) {
          return "Request cancelled.";
        }

        // Run auto-approved tools in parallel
        if (autoApproved.length > 0) {
          const parallelResults = await Promise.all(
            autoApproved.map(async (toolCall) => {
              const { name, arguments: args } = toolCall.function;
              this.callbacks.onToolCall?.(name, args);
              const result = await toolRegistry.execute(name, args);
              result.tool_call_id = toolCall.id;
              this.callbacks.onToolResult?.(name, result.content);
              return result;
            })
          );
          toolResults.push(...parallelResults);
        }

        // Run confirmation-required tools sequentially
        for (const toolCall of needsConfirmation) {
          const { name, arguments: args } = toolCall.function;

          this.callbacks.onToolCall?.(name, args);

          const confirmed = await this.callbacks.onToolConfirmation!(name, args);
          if (!confirmed) {
            toolResults.push({
              tool_call_id: toolCall.id,
              role: "tool",
              name,
              content: JSON.stringify({ rejected: true, message: "User rejected this tool execution" }),
            });
            this.callbacks.onToolResult?.(name, "Rejected by user");
            continue;
          }

          const result = await toolRegistry.execute(name, args);
          result.tool_call_id = toolCall.id;

          this.callbacks.onToolResult?.(name, result.content);
          toolResults.push(result);
        }

        // Add tool results to messages
        for (const result of toolResults) {
          this.messages.push({
            role: "tool",
            tool_call_id: result.tool_call_id,
            name: result.name,
            content: result.content,
          });
        }

        // Truncate context after adding tool results to stay within limits
        this.messages = contextManager.truncateToFit(this.messages);

        // Continue the loop to get the next response
        continue;
      }

      // No tool calls - we have a final response
      const finalContent = response.content || "";
      this.callbacks.onResponse?.(finalContent);
      return finalContent;
    }

    // Max iterations reached
    const errorMsg = "Maximum iterations reached. The agent may be stuck in a loop.";
    this.callbacks.onError?.(new Error(errorMsg));
    return errorMsg;
  }

  /**
   * Reset the conversation (keep system prompt)
   */
  reset(): void {
    const systemMessage = this.messages.find((m) => m.role === "system");
    this.messages = systemMessage ? [systemMessage] : [];
  }

  /**
   * Get conversation history
   */
  getHistory(): Message[] {
    return [...this.messages];
  }

  /**
   * Load messages from a saved session
   */
  loadMessages(messages: Message[]): void {
    // Keep system prompt, add saved messages
    const systemMessage = this.messages.find((m) => m.role === "system");
    const savedMessages = messages.filter((m) => m.role !== "system");
    this.messages = systemMessage ? [systemMessage, ...savedMessages] : savedMessages;
  }

  /**
   * Get messages for saving (excluding system prompt)
   */
  getMessagesForSave(): Message[] {
    return this.messages.filter((m) => m.role !== "system");
  }

  /**
   * Get context statistics
   */
  getContextStats(): string {
    return contextManager.formatStats(this.messages);
  }
}

