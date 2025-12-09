import { llmClient } from "./llm/client.ts";
import { toolRegistry } from "./tools/index.ts";
import { agentConfig } from "./config/index.ts";
import { contextManager } from "./llm/context.ts";
import { memoryManager } from "./memory/index.ts";
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
 */
function buildBaseSystemPrompt(toolNames: string[]): string {
  return `You are Clarissa, a helpful AI assistant with access to tools.

You can use the following tools:
${toolNames.map((name) => `- ${name}`).join("\n")}

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

  constructor(callbacks: AgentCallbacks = {}) {
    this.callbacks = callbacks;
    // System prompt will be initialized on first run with correct tool names
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
    // Get provider's max tools capability and select appropriate tool set
    // Do this FIRST so we can build the system prompt with correct tool names
    const maxTools = await llmClient.getMaxTools();
    const tools = toolRegistry.getDefinitionsLimited(maxTools);
    const toolNames = tools.map(t => t.function.name);

    // Update system prompt with current memories and tool names
    await this.updateSystemPrompt(toolNames);

    // Add user message
    this.messages.push({
      role: "user",
      content: userMessage,
    });

    // Truncate context if needed
    this.messages = contextManager.truncateToFit(this.messages);

    // Run the agent loop
    for (let i = 0; i < agentConfig.maxIterations; i++) {
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
        // Execute each tool call
        const toolResults: ToolResult[] = [];

        for (const toolCall of response.tool_calls) {
          const { name, arguments: args } = toolCall.function;

          this.callbacks.onToolCall?.(name, args);

          // Check if tool requires confirmation (skip if auto-approve is enabled)
          if (!agentConfig.autoApprove && toolRegistry.requiresConfirmation(name) && this.callbacks.onToolConfirmation) {
            const confirmed = await this.callbacks.onToolConfirmation(name, args);
            if (!confirmed) {
              // User rejected - add rejection message
              toolResults.push({
                tool_call_id: toolCall.id,
                role: "tool",
                name,
                content: JSON.stringify({ rejected: true, message: "User rejected this tool execution" }),
              });
              this.callbacks.onToolResult?.(name, "Rejected by user");
              continue;
            }
          }

          // Execute the tool
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

