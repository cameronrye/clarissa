import { z } from "zod";
import { defineTool } from "./base.ts";

/**
 * Token types for the expression parser
 */
type TokenType = "number" | "operator" | "function" | "constant" | "lparen" | "rparen" | "comma";

interface Token {
  type: TokenType;
  value: string | number;
}

/**
 * Safe math functions and constants
 */
const MATH_FUNCTIONS: Record<string, (...args: number[]) => number> = {
  sqrt: Math.sqrt,
  sin: Math.sin,
  cos: Math.cos,
  tan: Math.tan,
  log: Math.log,
  log10: Math.log10,
  log2: Math.log2,
  abs: Math.abs,
  floor: Math.floor,
  ceil: Math.ceil,
  round: Math.round,
  min: (...args) => Math.min(...args),
  max: (...args) => Math.max(...args),
  pow: Math.pow,
  exp: Math.exp,
};

const MATH_CONSTANTS: Record<string, number> = {
  PI: Math.PI,
  E: Math.E,
};

/**
 * Tokenize a mathematical expression
 */
function tokenize(expr: string): Token[] {
  const tokens: Token[] = [];
  let i = 0;

  while (i < expr.length) {
    const char = expr[i]!;

    // Skip whitespace
    if (/\s/.test(char)) {
      i++;
      continue;
    }

    // Numbers (including decimals)
    if (/\d/.test(char) || (char === "." && i + 1 < expr.length && /\d/.test(expr[i + 1]!))) {
      let num = "";
      while (i < expr.length && (/\d/.test(expr[i]!) || expr[i] === ".")) {
        num += expr[i];
        i++;
      }
      tokens.push({ type: "number", value: parseFloat(num) });
      continue;
    }

    // Exponentiation (** or ^) - check before single operators
    if (char === "*" && i + 1 < expr.length && expr[i + 1] === "*") {
      tokens.push({ type: "operator", value: "**" });
      i += 2;
      continue;
    }

    if (char === "^") {
      tokens.push({ type: "operator", value: "**" });
      i++;
      continue;
    }

    // Single-character operators
    if ("+-*/%".includes(char)) {
      tokens.push({ type: "operator", value: char });
      i++;
      continue;
    }

    // Parentheses
    if (char === "(") {
      tokens.push({ type: "lparen", value: "(" });
      i++;
      continue;
    }

    if (char === ")") {
      tokens.push({ type: "rparen", value: ")" });
      i++;
      continue;
    }

    // Comma (for function arguments)
    if (char === ",") {
      tokens.push({ type: "comma", value: "," });
      i++;
      continue;
    }

    // Identifiers (functions or constants)
    if (/[a-zA-Z_]/.test(char)) {
      let ident = "";
      while (i < expr.length && /[a-zA-Z0-9_]/.test(expr[i]!)) {
        ident += expr[i];
        i++;
      }
      const upperIdent = ident.toUpperCase();
      if (MATH_CONSTANTS[upperIdent] !== undefined) {
        tokens.push({ type: "constant", value: ident });
      } else if (MATH_FUNCTIONS[ident.toLowerCase()]) {
        tokens.push({ type: "function", value: ident.toLowerCase() });
      } else {
        throw new Error(`Unknown identifier: ${ident}`);
      }
      continue;
    }

    throw new Error(`Unexpected character: ${char}`);
  }

  return tokens;
}

/**
 * Recursive descent parser for mathematical expressions
 * Grammar:
 *   expr    -> term (('+' | '-') term)*
 *   term    -> power (('*' | '/' | '%') power)*
 *   power   -> unary ('**' unary)*
 *   unary   -> ('-' | '+')? factor
 *   factor  -> NUMBER | CONSTANT | function '(' args ')' | '(' expr ')'
 *   args    -> expr (',' expr)*
 */
class ExpressionParser {
  private tokens: Token[];
  private pos: number = 0;

  constructor(tokens: Token[]) {
    this.tokens = tokens;
  }

  private peek(): Token | undefined {
    return this.tokens[this.pos];
  }

  private consume(): Token {
    const token = this.tokens[this.pos];
    if (!token) throw new Error("Unexpected end of expression");
    this.pos++;
    return token;
  }

  private expect(type: TokenType): Token {
    const token = this.consume();
    if (token.type !== type) {
      throw new Error(`Expected ${type}, got ${token.type}`);
    }
    return token;
  }

  parse(): number {
    const result = this.parseExpr();
    if (this.pos < this.tokens.length) {
      throw new Error(`Unexpected token: ${this.peek()?.value}`);
    }
    return result;
  }

  private parseExpr(): number {
    let left = this.parseTerm();

    while (this.peek()?.type === "operator" && (this.peek()?.value === "+" || this.peek()?.value === "-")) {
      const op = this.consume().value as string;
      const right = this.parseTerm();
      left = op === "+" ? left + right : left - right;
    }

    return left;
  }

  private parseTerm(): number {
    let left = this.parsePower();

    while (this.peek()?.type === "operator" && ["*", "/", "%"].includes(this.peek()?.value as string)) {
      const op = this.consume().value as string;
      const right = this.parsePower();
      if (op === "*") left = left * right;
      else if (op === "/") left = left / right;
      else left = left % right;
    }

    return left;
  }

  private parsePower(): number {
    let base = this.parseUnary();

    while (this.peek()?.type === "operator" && this.peek()?.value === "**") {
      this.consume();
      const exp = this.parseUnary();
      base = Math.pow(base, exp);
    }

    return base;
  }

  private parseUnary(): number {
    if (this.peek()?.type === "operator" && (this.peek()?.value === "-" || this.peek()?.value === "+")) {
      const op = this.consume().value as string;
      const value = this.parseFactor();
      return op === "-" ? -value : value;
    }
    return this.parseFactor();
  }

  private parseFactor(): number {
    const token = this.peek();
    if (!token) throw new Error("Unexpected end of expression");

    if (token.type === "number") {
      this.consume();
      return token.value as number;
    }

    if (token.type === "constant") {
      this.consume();
      const name = (token.value as string).toUpperCase();
      const value = MATH_CONSTANTS[name];
      if (value === undefined) throw new Error(`Unknown constant: ${token.value}`);
      return value;
    }

    if (token.type === "function") {
      this.consume();
      const funcName = token.value as string;
      const func = MATH_FUNCTIONS[funcName];
      if (!func) throw new Error(`Unknown function: ${funcName}`);

      this.expect("lparen");
      const args = this.parseArgs();
      this.expect("rparen");

      return func(...args);
    }

    if (token.type === "lparen") {
      this.consume();
      const value = this.parseExpr();
      this.expect("rparen");
      return value;
    }

    throw new Error(`Unexpected token: ${token.value}`);
  }

  private parseArgs(): number[] {
    const args: number[] = [];

    if (this.peek()?.type === "rparen") {
      return args;
    }

    args.push(this.parseExpr());

    while (this.peek()?.type === "comma") {
      this.consume();
      args.push(this.parseExpr());
    }

    return args;
  }
}

/**
 * Safely evaluate a mathematical expression
 */
function safeEvaluate(expression: string): number {
  const tokens = tokenize(expression);
  if (tokens.length === 0) {
    throw new Error("Empty expression");
  }
  const parser = new ExpressionParser(tokens);
  return parser.parse();
}

/**
 * Calculator tool for mathematical expressions
 */
export const calculatorTool = defineTool({
  name: "calculator",
  description:
    "Evaluate mathematical expressions. Supports basic arithmetic (+, -, *, /), exponents (** or ^), parentheses, and common math functions (sqrt, sin, cos, tan, log, abs, floor, ceil, round, min, max, pow, exp) and constants (PI, E).",
  parameters: z.object({
    expression: z
      .string()
      .describe("The mathematical expression to evaluate, e.g., '2 + 2' or 'sqrt(16) * 2'"),
  }),
  execute: async ({ expression }) => {
    try {
      const result = safeEvaluate(expression);

      if (typeof result !== "number" || !isFinite(result)) {
        throw new Error("Expression did not evaluate to a valid number");
      }

      return {
        expression,
        result,
        formatted: Number.isInteger(result) ? result.toString() : result.toFixed(10).replace(/\.?0+$/, ""),
      };
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unknown error";
      throw new Error(`Failed to evaluate expression: ${message}`);
    }
  },
});

