import { describe, test, expect } from "bun:test";
import { calculatorTool } from "./calculator.ts";

describe("calculator tool", () => {
  describe("basic arithmetic", () => {
    test("addition", async () => {
      const result = await calculatorTool.execute({ expression: "2 + 2" });
      expect(result.result).toBe(4);
    });

    test("subtraction", async () => {
      const result = await calculatorTool.execute({ expression: "10 - 3" });
      expect(result.result).toBe(7);
    });

    test("multiplication", async () => {
      const result = await calculatorTool.execute({ expression: "6 * 7" });
      expect(result.result).toBe(42);
    });

    test("division", async () => {
      const result = await calculatorTool.execute({ expression: "15 / 3" });
      expect(result.result).toBe(5);
    });

    test("modulo", async () => {
      const result = await calculatorTool.execute({ expression: "17 % 5" });
      expect(result.result).toBe(2);
    });
  });

  describe("operator precedence", () => {
    test("multiplication before addition", async () => {
      const result = await calculatorTool.execute({ expression: "2 + 3 * 4" });
      expect(result.result).toBe(14);
    });

    test("parentheses override precedence", async () => {
      const result = await calculatorTool.execute({ expression: "(2 + 3) * 4" });
      expect(result.result).toBe(20);
    });
  });

  describe("exponentiation", () => {
    test("with ** operator", async () => {
      const result = await calculatorTool.execute({ expression: "2 ** 8" });
      expect(result.result).toBe(256);
    });

    test("with ^ operator", async () => {
      const result = await calculatorTool.execute({ expression: "2 ^ 10" });
      expect(result.result).toBe(1024);
    });
  });

  describe("unary operators", () => {
    test("negative number", async () => {
      const result = await calculatorTool.execute({ expression: "-5 + 10" });
      expect(result.result).toBe(5);
    });

    test("positive number", async () => {
      const result = await calculatorTool.execute({ expression: "+5 + 5" });
      expect(result.result).toBe(10);
    });
  });

  describe("math functions", () => {
    test("sqrt", async () => {
      const result = await calculatorTool.execute({ expression: "sqrt(16)" });
      expect(result.result).toBe(4);
    });

    test("sin", async () => {
      const result = await calculatorTool.execute({ expression: "sin(0)" });
      expect(result.result).toBe(0);
    });

    test("cos", async () => {
      const result = await calculatorTool.execute({ expression: "cos(0)" });
      expect(result.result).toBe(1);
    });

    test("abs", async () => {
      const result = await calculatorTool.execute({ expression: "abs(-42)" });
      expect(result.result).toBe(42);
    });

    test("floor", async () => {
      const result = await calculatorTool.execute({ expression: "floor(3.7)" });
      expect(result.result).toBe(3);
    });

    test("ceil", async () => {
      const result = await calculatorTool.execute({ expression: "ceil(3.2)" });
      expect(result.result).toBe(4);
    });

    test("round", async () => {
      const result = await calculatorTool.execute({ expression: "round(3.5)" });
      expect(result.result).toBe(4);
    });

    test("min with multiple args", async () => {
      const result = await calculatorTool.execute({ expression: "min(5, 2, 8, 1)" });
      expect(result.result).toBe(1);
    });

    test("max with multiple args", async () => {
      const result = await calculatorTool.execute({ expression: "max(5, 2, 8, 1)" });
      expect(result.result).toBe(8);
    });

    test("pow", async () => {
      const result = await calculatorTool.execute({ expression: "pow(2, 3)" });
      expect(result.result).toBe(8);
    });
  });

  describe("constants", () => {
    test("PI", async () => {
      const result = await calculatorTool.execute({ expression: "PI" });
      expect(result.result).toBeCloseTo(Math.PI);
    });

    test("E", async () => {
      const result = await calculatorTool.execute({ expression: "E" });
      expect(result.result).toBeCloseTo(Math.E);
    });
  });

  describe("error handling", () => {
    test("unknown identifier", async () => {
      await expect(calculatorTool.execute({ expression: "foo + 1" })).rejects.toThrow();
    });

    test("division by zero throws error", async () => {
      await expect(calculatorTool.execute({ expression: "1 / 0" })).rejects.toThrow();
    });

    test("empty expression", async () => {
      await expect(calculatorTool.execute({ expression: "" })).rejects.toThrow();
    });
  });
});

