import type { AnyTool, ToolPriority } from "./base.ts";
import { toolToDefinition } from "./base.ts";
import { calculatorTool } from "./calculator.ts";
import { bashTool } from "./bash.ts";
import { readFileTool } from "./file-read.ts";
import { writeFileTool } from "./file-write.ts";
import { patchFileTool } from "./file-patch.ts";
import { listDirectoryTool } from "./file-list.ts";
import { searchFilesTool } from "./file-search.ts";
import {
  gitStatusTool,
  gitDiffTool,
  gitLogTool,
  gitAddTool,
  gitCommitTool,
  gitBranchTool,
} from "./git.ts";
import { webFetchTool } from "./web-fetch.ts";
import { semanticSearchTool } from "./semantic-search.ts";
import type { ToolDefinition, ToolResult } from "../llm/types.ts";

/** Debug logging for tool execution (matches iOS pattern) */
const DEBUG = process.env.DEBUG === "true" || process.env.DEBUG === "1";

function logToolCall(name: string, args: string): void {
  if (DEBUG) {
    console.debug(`[Tool Call] ${name}`);
    try {
      const parsed = JSON.parse(args);
      console.debug(`  Args: ${JSON.stringify(parsed, null, 2).split("\n").join("\n  ")}`);
    } catch {
      console.debug(`  Args: ${args}`);
    }
  }
}

function logToolResult(name: string, result: string, durationMs: number): void {
  if (DEBUG) {
    const truncated = result.length > 500 ? result.slice(0, 500) + "..." : result;
    console.debug(`[Tool Result] ${name} (${durationMs}ms)`);
    console.debug(`  Result: ${truncated.split("\n").join("\n  ")}`);
  }
}

function logToolError(name: string, error: string): void {
  if (DEBUG) {
    console.debug(`[Tool Error] ${name}`);
    console.debug(`  Error: ${error}`);
  }
}

/**
 * Registry of all available tools
 */
class ToolRegistry {
  private tools: Map<string, AnyTool> = new Map();

  constructor() {
    // Register core tools (priority 1) - essential for basic operations
    this.register({ ...calculatorTool, priority: 1 as ToolPriority });
    this.register({ ...bashTool, priority: 1 as ToolPriority });
    this.register({ ...readFileTool, priority: 1 as ToolPriority });
    this.register({ ...writeFileTool, priority: 1 as ToolPriority });

    // Register important tools (priority 2) - commonly used
    this.register({ ...listDirectoryTool, priority: 2 as ToolPriority });
    this.register({ ...patchFileTool, priority: 2 as ToolPriority });
    this.register({ ...searchFilesTool, priority: 2 as ToolPriority });
    this.register({ ...gitStatusTool, priority: 2 as ToolPriority });
    this.register({ ...gitDiffTool, priority: 2 as ToolPriority });

    // Register extended tools (priority 3) - specialized
    this.register({ ...gitLogTool, priority: 3 as ToolPriority });
    this.register({ ...gitAddTool, priority: 3 as ToolPriority });
    this.register({ ...gitCommitTool, priority: 3 as ToolPriority });
    this.register({ ...gitBranchTool, priority: 3 as ToolPriority });
    this.register({ ...webFetchTool, priority: 3 as ToolPriority });
    this.register({ ...semanticSearchTool, priority: 2 as ToolPriority });
  }

  /**
   * Register a new tool
   */
  register(tool: AnyTool): void {
    if (this.tools.has(tool.name)) {
      console.warn(`[ToolRegistry] Warning: Overwriting existing tool "${tool.name}"`);
    }
    this.tools.set(tool.name, tool);
  }

  /**
   * Get a tool by name
   */
  get(name: string): AnyTool | undefined {
    return this.tools.get(name);
  }

  /**
   * Get all tools as OpenRouter ToolDefinitions
   */
  getDefinitions(): ToolDefinition[] {
    return Array.from(this.tools.values()).map(toolToDefinition);
  }

  /**
   * Get tools sorted by priority (1=core, 2=important, 3=extended)
   */
  private getToolsSortedByPriority(): AnyTool[] {
    return Array.from(this.tools.values()).sort((a, b) => {
      const priorityA = a.priority ?? 3;
      const priorityB = b.priority ?? 3;
      return priorityA - priorityB;
    });
  }

  /**
   * Get tool definitions limited by max count, prioritizing higher priority tools
   * @param maxTools - Maximum number of tools to return (undefined = all)
   */
  getDefinitionsLimited(maxTools?: number): ToolDefinition[] {
    if (maxTools === undefined) {
      return this.getDefinitions();
    }

    const sortedTools = this.getToolsSortedByPriority();
    const limitedTools = sortedTools.slice(0, maxTools);
    return limitedTools.map(toolToDefinition);
  }

  /**
   * Get core tools only (priority 1)
   */
  getCoreDefinitions(): ToolDefinition[] {
    return Array.from(this.tools.values())
      .filter((t) => t.priority === 1)
      .map(toolToDefinition);
  }

  /**
   * Get core + important tools (priority 1 and 2)
   */
  getImportantDefinitions(): ToolDefinition[] {
    return Array.from(this.tools.values())
      .filter((t) => (t.priority ?? 3) <= 2)
      .map(toolToDefinition);
  }

  /**
   * Execute a tool by name with given arguments
   */
  async execute(name: string, args: string): Promise<ToolResult> {
    const tool = this.tools.get(name);
    if (!tool) {
      const errorContent = JSON.stringify({ error: `Tool "${name}" not found` });
      logToolError(name, `Tool not found`);
      return {
        tool_call_id: "",
        role: "tool",
        name,
        content: errorContent,
      };
    }

    // Log tool call (iOS pattern)
    logToolCall(name, args);
    const startTime = Date.now();

    try {
      // Parse and validate arguments
      const parsedArgs = JSON.parse(args);
      const validatedArgs = tool.parameters.parse(parsedArgs);

      // Execute the tool
      const result = await tool.execute(validatedArgs);
      const content = typeof result === "string" ? result : JSON.stringify(result);

      // Log tool result (iOS pattern)
      logToolResult(name, content, Date.now() - startTime);

      return {
        tool_call_id: "",
        role: "tool",
        name,
        content,
      };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logToolError(name, errorMessage);
      return {
        tool_call_id: "",
        role: "tool",
        name,
        content: JSON.stringify({ error: errorMessage }),
      };
    }
  }

  /**
   * Get list of tool names
   */
  getToolNames(): string[] {
    return Array.from(this.tools.keys());
  }

  /**
   * Check if a tool requires confirmation before execution
   */
  requiresConfirmation(name: string): boolean {
    const tool = this.tools.get(name);
    return tool?.requiresConfirmation ?? false;
  }

  /**
   * Register multiple tools at once (for MCP)
   */
  registerMany(tools: AnyTool[]): void {
    for (const tool of tools) {
      this.register(tool);
    }
  }

  /**
   * Unregister a tool by name
   */
  unregister(name: string): void {
    this.tools.delete(name);
  }

  /**
   * Get tools by category
   */
  getByCategory(category: string): AnyTool[] {
    return Array.from(this.tools.values()).filter((t) => t.category === category);
  }
}

export const toolRegistry = new ToolRegistry();
export { defineTool, type Tool, type ToolCategory, type ToolPriority, type AnyTool } from "./base.ts";

