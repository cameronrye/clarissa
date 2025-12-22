import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import type { Tool } from "../tools/base.ts";
import { z } from "zod";
import { getMcpServers, type MCPServerFileConfig } from "../config/index.ts";

/**
 * Convert JSON Schema to Zod schema
 * Exported for testing
 */
export function jsonSchemaToZod(schema: unknown): z.ZodType {
  if (!schema || typeof schema !== "object") {
    return z.record(z.string(), z.unknown());
  }

  const s = schema as Record<string, unknown>;

  if (s.type === "object" && s.properties) {
    const props = s.properties as Record<string, unknown>;
    const required = (s.required as string[]) || [];

    const shape: Record<string, z.ZodType> = {};

    for (const [key, propSchema] of Object.entries(props)) {
      let zodType = jsonSchemaToZod(propSchema);
      if (!required.includes(key)) {
        zodType = zodType.optional();
      }
      shape[key] = zodType;
    }

    return z.object(shape);
  }

  if (s.type === "string") {
    // Handle enum values
    if (Array.isArray(s.enum) && s.enum.length > 0) {
      const enumValues = s.enum as [string, ...string[]];
      return z.enum(enumValues);
    }
    return z.string();
  }

  if (s.type === "number" || s.type === "integer") {
    let numSchema = z.number();
    if (s.type === "integer") {
      numSchema = numSchema.int();
    }
    if (typeof s.minimum === "number") {
      numSchema = numSchema.min(s.minimum);
    }
    if (typeof s.maximum === "number") {
      numSchema = numSchema.max(s.maximum);
    }
    return numSchema;
  }

  if (s.type === "boolean") return z.boolean();
  if (s.type === "null") return z.null();

  if (s.type === "array" && s.items) {
    let arrSchema = z.array(jsonSchemaToZod(s.items));
    if (typeof s.minItems === "number") {
      arrSchema = arrSchema.min(s.minItems);
    }
    if (typeof s.maxItems === "number") {
      arrSchema = arrSchema.max(s.maxItems);
    }
    return arrSchema;
  }

  // Handle anyOf, oneOf
  if (Array.isArray(s.anyOf) && s.anyOf.length > 0) {
    const schemas = s.anyOf.map((subSchema) => jsonSchemaToZod(subSchema));
    if (schemas.length === 1) return schemas[0]!;
    return z.union([schemas[0]!, schemas[1]!, ...schemas.slice(2)] as [z.ZodType, z.ZodType, ...z.ZodType[]]);
  }

  if (Array.isArray(s.oneOf) && s.oneOf.length > 0) {
    const schemas = s.oneOf.map((subSchema) => jsonSchemaToZod(subSchema));
    if (schemas.length === 1) return schemas[0]!;
    return z.union([schemas[0]!, schemas[1]!, ...schemas.slice(2)] as [z.ZodType, z.ZodType, ...z.ZodType[]]);
  }

  return z.unknown();
}

export interface MCPServerConfig {
  name: string;
  command: string;
  args?: string[];
  env?: Record<string, string>;
}

interface MCPConnection {
  client: Client;
  transport: StdioClientTransport;
  tools: Tool[];
}

/**
 * MCP Client Manager - connects to MCP servers and exposes their tools
 */
class MCPClientManager {
  private connections: Map<string, MCPConnection> = new Map();

  /**
   * Connect to an MCP server
   */
  async connect(config: MCPServerConfig): Promise<Tool[]> {
    if (this.connections.has(config.name)) {
      return this.connections.get(config.name)!.tools;
    }

    const transport = new StdioClientTransport({
      command: config.command,
      args: config.args,
      env: config.env,
    });

    const client = new Client(
      { name: "clarissa", version: "1.0.0" },
      { capabilities: {} }
    );

    await client.connect(transport);

    // Get available tools from the server
    const { tools: mcpTools } = await client.listTools();

    // Convert MCP tools to Clarissa tools
    const tools: Tool[] = mcpTools.map((mcpTool) => this.convertTool(config.name, client, mcpTool));

    this.connections.set(config.name, { client, transport, tools });

    return tools;
  }

  /**
   * Convert an MCP tool to a Clarissa tool
   */
  private convertTool(
    serverName: string,
    client: Client,
    mcpTool: { name: string; description?: string; inputSchema?: unknown }
  ): Tool {
    // Create a dynamic Zod schema from the MCP tool's input schema
    const parameters = jsonSchemaToZod(mcpTool.inputSchema);

    return {
      name: `mcp_${serverName}_${mcpTool.name}`,
      description: mcpTool.description || `MCP tool: ${mcpTool.name}`,
      category: "mcp",
      requiresConfirmation: true, // MCP tools are external, require confirmation
      parameters,
      execute: async (input: unknown) => {
        const result = await client.callTool({
          name: mcpTool.name,
          arguments: input as Record<string, unknown>,
        });

        // Handle different result types
        if (result.content && Array.isArray(result.content)) {
          return result.content
            .map((c) => {
              if (c.type === "text") return c.text;
              return JSON.stringify(c);
            })
            .join("\n");
        }

        return JSON.stringify(result);
      },
    };
  }

  /**
   * Disconnect from an MCP server
   */
  async disconnect(name: string): Promise<void> {
    const connection = this.connections.get(name);
    if (connection) {
      await connection.client.close();
      this.connections.delete(name);
    }
  }

  /**
   * Disconnect from all servers
   */
  async disconnectAll(): Promise<void> {
    for (const name of this.connections.keys()) {
      await this.disconnect(name);
    }
  }

  /**
   * Get all tools from connected servers
   */
  getAllTools(): Tool[] {
    const tools: Tool[] = [];
    for (const connection of this.connections.values()) {
      tools.push(...connection.tools);
    }
    return tools;
  }

  /**
   * Get connected server names
   */
  getConnectedServers(): string[] {
    return Array.from(this.connections.keys());
  }

  /**
   * Get server info with tool count
   */
  getServerInfo(): Array<{ name: string; toolCount: number }> {
    return Array.from(this.connections.entries()).map(([name, conn]) => ({
      name,
      toolCount: conn.tools.length,
    }));
  }

  /**
   * Get configured servers from config file
   */
  getConfiguredServers(): Record<string, MCPServerFileConfig> {
    return getMcpServers();
  }

  /**
   * Load all MCP servers from config file
   */
  async loadConfiguredServers(): Promise<{ name: string; tools: Tool[]; error?: string }[]> {
    const servers = getMcpServers();
    const results: { name: string; tools: Tool[]; error?: string }[] = [];

    for (const [name, serverConfig] of Object.entries(servers)) {
      try {
        const tools = await this.connect({
          name,
          command: serverConfig.command,
          args: serverConfig.args,
          env: serverConfig.env,
        });
        results.push({ name, tools });
      } catch (error) {
        const msg = error instanceof Error ? error.message : "Connection failed";
        results.push({ name, tools: [], error: msg });
      }
    }

    return results;
  }

  /**
   * Register cleanup handlers for process exit
   */
  registerCleanupHandlers(): void {
    let isCleaningUp = false;

    const cleanup = async (): Promise<void> => {
      if (isCleaningUp) return;
      isCleaningUp = true;

      const closePromises: Promise<void>[] = [];
      for (const connection of this.connections.values()) {
        closePromises.push(
          Promise.resolve(connection.client.close()).catch(() => {
            // Ignore errors during cleanup
          })
        );
      }
      await Promise.allSettled(closePromises);
      this.connections.clear();
    };

    // Sync cleanup for normal exit (can't await here)
    process.on("exit", () => {
      for (const connection of this.connections.values()) {
        try {
          connection.client.close();
        } catch {
          // Ignore errors during cleanup
        }
      }
    });

    // Async cleanup for signals - wait for completion before exit
    process.on("SIGINT", () => {
      cleanup().finally(() => process.exit(0));
    });
    process.on("SIGTERM", () => {
      cleanup().finally(() => process.exit(0));
    });
  }
}

export const mcpClient = new MCPClientManager();

// Register cleanup handlers on module load
mcpClient.registerCleanupHandlers();

