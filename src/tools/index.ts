import type { AnyTool } from "./base.ts";
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
import type { ToolDefinition, ToolResult } from "../llm/types.ts";

/**
 * Registry of all available tools
 */
class ToolRegistry {
  private tools: Map<string, AnyTool> = new Map();

  constructor() {
    // Register file tools
    this.register(readFileTool);
    this.register(writeFileTool);
    this.register(patchFileTool);
    this.register(listDirectoryTool);
    this.register(searchFilesTool);

    // Register git tools
    this.register(gitStatusTool);
    this.register(gitDiffTool);
    this.register(gitLogTool);
    this.register(gitAddTool);
    this.register(gitCommitTool);
    this.register(gitBranchTool);

    // Register system tools
    this.register(calculatorTool);
    this.register(bashTool);

    // Register utility tools
    this.register(webFetchTool);
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
   * Execute a tool by name with given arguments
   */
  async execute(name: string, args: string): Promise<ToolResult> {
    const tool = this.tools.get(name);
    if (!tool) {
      return {
        tool_call_id: "",
        role: "tool",
        name,
        content: JSON.stringify({ error: `Tool "${name}" not found` }),
      };
    }

    try {
      // Parse and validate arguments
      const parsedArgs = JSON.parse(args);
      const validatedArgs = tool.parameters.parse(parsedArgs);
      
      // Execute the tool
      const result = await tool.execute(validatedArgs);
      
      return {
        tool_call_id: "",
        role: "tool",
        name,
        content: typeof result === "string" ? result : JSON.stringify(result),
      };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
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
export { defineTool, type Tool, type ToolCategory, type AnyTool } from "./base.ts";

