import { z, type ZodType } from "zod";
import type { ToolDefinition } from "../llm/types.ts";

/**
 * Tool categories for organization
 */
export type ToolCategory = "file" | "git" | "system" | "mcp" | "utility";

/**
 * Internal Zod definition structure for type inspection
 */
interface ZodDef {
  typeName?: string;
  description?: string;
  type?: ZodType;
  innerType?: ZodType;
}

/**
 * Safely cast Zod internal definition
 */
function getZodDef(schema: ZodType): ZodDef {
  return schema._def as unknown as ZodDef;
}

/**
 * Base interface for a tool that the agent can use
 */
export interface Tool<TInput = unknown, TOutput = unknown> {
  name: string;
  description: string;
  category?: ToolCategory;
  requiresConfirmation?: boolean;
  parameters: ZodType<TInput>;
  execute: (input: TInput) => Promise<TOutput>;
}

/**
 * Type alias for tools with any input/output for registry use
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export type AnyTool = Tool<any, any>;

/**
 * Convert a Zod schema to JSON Schema for OpenRouter API
 */
function zodToJsonSchema(schema: ZodType): Record<string, unknown> {
  // Simple conversion for common Zod types
  // For production, consider using zod-to-json-schema package
  const def = getZodDef(schema);
  const typeName = def.typeName;

  if (typeName === "ZodObject") {
    const shape = (schema as z.ZodObject<z.ZodRawShape>).shape;
    const properties: Record<string, unknown> = {};
    const required: string[] = [];

    for (const [key, value] of Object.entries(shape)) {
      const zodValue = value as ZodType;
      properties[key] = zodToJsonSchema(zodValue);

      // Check if field is optional
      const innerDef = getZodDef(zodValue);
      if (innerDef.typeName !== "ZodOptional") {
        required.push(key);
      }
    }

    return {
      type: "object",
      properties,
      required: required.length > 0 ? required : undefined,
    };
  }

  if (typeName === "ZodString") {
    const result: Record<string, unknown> = { type: "string" };
    if (def.description) result.description = def.description;
    return result;
  }

  if (typeName === "ZodNumber") {
    const result: Record<string, unknown> = { type: "number" };
    if (def.description) result.description = def.description;
    return result;
  }

  if (typeName === "ZodBoolean") {
    const result: Record<string, unknown> = { type: "boolean" };
    if (def.description) result.description = def.description;
    return result;
  }

  if (typeName === "ZodArray" && def.type) {
    return {
      type: "array",
      items: zodToJsonSchema(def.type),
    };
  }

  if (typeName === "ZodOptional" && def.innerType) {
    return zodToJsonSchema(def.innerType);
  }

  if (typeName === "ZodDefault" && def.innerType) {
    return zodToJsonSchema(def.innerType);
  }

  // Fallback
  return { type: "string" };
}

/**
 * Convert a Tool to OpenRouter ToolDefinition format
 */
export function toolToDefinition(tool: Tool): ToolDefinition {
  const jsonSchema = zodToJsonSchema(tool.parameters);

  return {
    type: "function",
    function: {
      name: tool.name,
      description: tool.description,
      parameters: jsonSchema as ToolDefinition["function"]["parameters"],
    },
  };
}

/**
 * Helper to define a tool with proper typing
 */
export function defineTool<TInput, TOutput>(
  tool: Tool<TInput, TOutput>
): Tool<TInput, TOutput> {
  return tool;
}

