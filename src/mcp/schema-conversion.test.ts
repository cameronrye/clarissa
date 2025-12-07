import { test, expect, describe } from "bun:test";
import { jsonSchemaToZod } from "./client.ts";

/**
 * Test the JSON Schema to Zod conversion logic used by MCP client
 * Uses the production jsonSchemaToZod function from client.ts
 */

describe("MCP Schema Conversion", () => {
  describe("jsonSchemaToZod", () => {
    test("converts string type", () => {
      const schema = { type: "string" };
      const zodSchema = jsonSchemaToZod(schema);
      expect(zodSchema.parse("hello")).toBe("hello");
      expect(() => zodSchema.parse(123)).toThrow();
    });

    test("converts number type", () => {
      const schema = { type: "number" };
      const zodSchema = jsonSchemaToZod(schema);
      expect(zodSchema.parse(42)).toBe(42);
      expect(() => zodSchema.parse("not a number")).toThrow();
    });

    test("converts boolean type", () => {
      const schema = { type: "boolean" };
      const zodSchema = jsonSchemaToZod(schema);
      expect(zodSchema.parse(true)).toBe(true);
      expect(zodSchema.parse(false)).toBe(false);
      expect(() => zodSchema.parse("true")).toThrow();
    });

    test("converts array type", () => {
      const schema = { type: "array", items: { type: "string" } };
      const zodSchema = jsonSchemaToZod(schema);
      expect(zodSchema.parse(["a", "b"])).toEqual(["a", "b"]);
      expect(() => zodSchema.parse([1, 2])).toThrow();
    });

    test("converts object type with properties", () => {
      const schema = {
        type: "object",
        properties: {
          name: { type: "string" },
          age: { type: "number" },
        },
        required: ["name"],
      };
      const zodSchema = jsonSchemaToZod(schema);
      
      // Valid with required field
      expect(zodSchema.parse({ name: "John", age: 30 })).toEqual({ name: "John", age: 30 });
      expect(zodSchema.parse({ name: "Jane" })).toEqual({ name: "Jane" });
      
      // Invalid without required field
      expect(() => zodSchema.parse({ age: 30 })).toThrow();
    });

    test("handles optional properties", () => {
      const schema = {
        type: "object",
        properties: {
          required_field: { type: "string" },
          optional_field: { type: "number" },
        },
        required: ["required_field"],
      };
      const zodSchema = jsonSchemaToZod(schema);
      
      // Works without optional field
      expect(zodSchema.parse({ required_field: "test" })).toEqual({ required_field: "test" });
    });

    test("handles nested objects", () => {
      const schema = {
        type: "object",
        properties: {
          user: {
            type: "object",
            properties: {
              name: { type: "string" },
            },
            required: ["name"],
          },
        },
        required: ["user"],
      };
      const zodSchema = jsonSchemaToZod(schema);
      expect(zodSchema.parse({ user: { name: "John" } })).toEqual({ user: { name: "John" } });
    });

    test("handles null/undefined schema", () => {
      // When schema is null, function should return a fallback schema
      // Just verify it returns a ZodType without throwing
      const zodSchema = jsonSchemaToZod(null);
      expect(zodSchema).toBeDefined();
      // The schema should be some form of Zod type
      expect(typeof zodSchema.safeParse).toBe("function");
    });

    test("handles unknown types", () => {
      const schema = { type: "custom_type" };
      const zodSchema = jsonSchemaToZod(schema);
      // Unknown types should accept anything
      expect(() => zodSchema.parse("anything")).not.toThrow();
    });

    test("handles array of objects", () => {
      const schema = {
        type: "array",
        items: {
          type: "object",
          properties: {
            id: { type: "number" },
          },
          required: ["id"],
        },
      };
      const zodSchema = jsonSchemaToZod(schema);
      expect(zodSchema.parse([{ id: 1 }, { id: 2 }])).toEqual([{ id: 1 }, { id: 2 }]);
    });

    test("handles string enums", () => {
      const schema = {
        type: "string",
        enum: ["red", "green", "blue"],
      };
      const zodSchema = jsonSchemaToZod(schema);
      expect(zodSchema.parse("red")).toBe("red");
      expect(zodSchema.parse("green")).toBe("green");
      expect(() => zodSchema.parse("yellow")).toThrow();
    });

    test("handles integer type with constraints", () => {
      const schema = {
        type: "integer",
        minimum: 0,
        maximum: 100,
      };
      const zodSchema = jsonSchemaToZod(schema);
      expect(zodSchema.parse(50)).toBe(50);
      expect(() => zodSchema.parse(3.14)).toThrow();
      expect(() => zodSchema.parse(-1)).toThrow();
      expect(() => zodSchema.parse(101)).toThrow();
    });

    test("handles array with minItems and maxItems", () => {
      const schema = {
        type: "array",
        items: { type: "string" },
        minItems: 1,
        maxItems: 3,
      };
      const zodSchema = jsonSchemaToZod(schema);
      expect(zodSchema.parse(["a"])).toEqual(["a"]);
      expect(zodSchema.parse(["a", "b", "c"])).toEqual(["a", "b", "c"]);
      expect(() => zodSchema.parse([])).toThrow();
      expect(() => zodSchema.parse(["a", "b", "c", "d"])).toThrow();
    });

    test("handles null type", () => {
      const schema = { type: "null" };
      const zodSchema = jsonSchemaToZod(schema);
      expect(zodSchema.parse(null)).toBe(null);
      expect(() => zodSchema.parse("not null")).toThrow();
    });

    test("handles anyOf", () => {
      const schema = {
        anyOf: [{ type: "string" }, { type: "number" }],
      };
      const zodSchema = jsonSchemaToZod(schema);
      expect(zodSchema.parse("hello")).toBe("hello");
      expect(zodSchema.parse(42)).toBe(42);
      expect(() => zodSchema.parse(true)).toThrow();
    });

    test("handles oneOf", () => {
      const schema = {
        oneOf: [{ type: "boolean" }, { type: "null" }],
      };
      const zodSchema = jsonSchemaToZod(schema);
      expect(zodSchema.parse(true)).toBe(true);
      expect(zodSchema.parse(null)).toBe(null);
      expect(() => zodSchema.parse("string")).toThrow();
    });
  });
});

