import { test, expect, describe } from "bun:test";
import { jsonSchemaToZod } from "./client.ts";

/**
 * Test MCP client tool conversion logic using the production jsonSchemaToZod function
 */

// Mock MCP tool structure
interface MockMCPTool {
  name: string;
  description?: string;
  inputSchema?: unknown;
}

// Helper to convert MCP tool to Clarissa tool format
function convertMCPTool(serverName: string, mcpTool: MockMCPTool) {
  const parameters = jsonSchemaToZod(mcpTool.inputSchema);
  return {
    name: `mcp_${serverName}_${mcpTool.name}`,
    description: mcpTool.description || `MCP tool: ${mcpTool.name}`,
    category: "mcp" as const,
    requiresConfirmation: true,
    parameters,
  };
}

describe("MCP Client", () => {
  describe("Tool Conversion", () => {
    test("generates correct tool name", () => {
      const mcpTool: MockMCPTool = {
        name: "read_file",
        description: "Read a file",
      };
      const tool = convertMCPTool("filesystem", mcpTool);
      expect(tool.name).toBe("mcp_filesystem_read_file");
    });

    test("uses provided description", () => {
      const mcpTool: MockMCPTool = {
        name: "test",
        description: "Custom description",
      };
      const tool = convertMCPTool("server", mcpTool);
      expect(tool.description).toBe("Custom description");
    });

    test("generates default description when not provided", () => {
      const mcpTool: MockMCPTool = {
        name: "test",
      };
      const tool = convertMCPTool("server", mcpTool);
      expect(tool.description).toBe("MCP tool: test");
    });

    test("sets category to mcp", () => {
      const mcpTool: MockMCPTool = { name: "test" };
      const tool = convertMCPTool("server", mcpTool);
      expect(tool.category).toBe("mcp");
    });

    test("requires confirmation for MCP tools", () => {
      const mcpTool: MockMCPTool = { name: "test" };
      const tool = convertMCPTool("server", mcpTool);
      expect(tool.requiresConfirmation).toBe(true);
    });

    test("converts input schema to Zod", () => {
      const mcpTool: MockMCPTool = {
        name: "search",
        inputSchema: {
          type: "object",
          properties: {
            query: { type: "string" },
            limit: { type: "number" },
          },
          required: ["query"],
        },
      };
      const tool = convertMCPTool("server", mcpTool);
      
      // Valid input
      expect(tool.parameters.parse({ query: "test" })).toEqual({ query: "test" });
      expect(tool.parameters.parse({ query: "test", limit: 10 })).toEqual({ query: "test", limit: 10 });
      
      // Invalid input
      expect(() => tool.parameters.parse({})).toThrow();
    });

    test("handles empty input schema", () => {
      const mcpTool: MockMCPTool = {
        name: "no_params",
      };
      const tool = convertMCPTool("server", mcpTool);
      // Should accept any record
      expect(tool.parameters.parse({})).toEqual({});
    });
  });

  describe("Server Name Prefixing", () => {
    test("prefixes tools from different servers", () => {
      const tool1 = convertMCPTool("server1", { name: "action" });
      const tool2 = convertMCPTool("server2", { name: "action" });
      
      expect(tool1.name).toBe("mcp_server1_action");
      expect(tool2.name).toBe("mcp_server2_action");
      expect(tool1.name).not.toBe(tool2.name);
    });

    test("handles special characters in server name", () => {
      const tool = convertMCPTool("my-server", { name: "do_thing" });
      expect(tool.name).toBe("mcp_my-server_do_thing");
    });
  });
});

