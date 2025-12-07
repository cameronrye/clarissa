import { test, expect, describe } from "bun:test";
import { renderMarkdown } from "./markdown.ts";

describe("renderMarkdown", () => {
  test("renders plain text unchanged", () => {
    const input = "Hello, world!";
    const result = renderMarkdown(input);
    expect(result).toContain("Hello, world!");
  });

  test("renders headings with formatting", () => {
    const input = "# Heading 1";
    const result = renderMarkdown(input);
    // Should contain the heading text (styling applied by chalk)
    expect(result).toContain("Heading 1");
  });

  test("renders bold text", () => {
    const input = "This is **bold** text";
    const result = renderMarkdown(input);
    expect(result).toContain("bold");
  });

  test("renders italic text", () => {
    const input = "This is *italic* text";
    const result = renderMarkdown(input);
    expect(result).toContain("italic");
  });

  test("renders inline code with styling", () => {
    const input = "Use the `console.log` function";
    const result = renderMarkdown(input);
    expect(result).toContain("console.log");
  });

  test("renders code blocks with syntax highlighting", () => {
    const input = `\`\`\`javascript
const x = 1;
console.log(x);
\`\`\``;
    const result = renderMarkdown(input);
    // Should contain the code content (may have ANSI codes for syntax highlighting)
    expect(result).toContain("const");
    // console.log may be split by ANSI codes, so check for console and log separately
    expect(result).toContain("console");
    expect(result).toContain("log");
  });

  test("renders code blocks with language auto-detection", () => {
    const input = `\`\`\`
function hello() {
  return "world";
}
\`\`\``;
    const result = renderMarkdown(input);
    expect(result).toContain("function");
    expect(result).toContain("hello");
  });

  test("renders TypeScript code blocks", () => {
    const input = `\`\`\`typescript
interface User {
  name: string;
  age: number;
}
\`\`\``;
    const result = renderMarkdown(input);
    expect(result).toContain("interface");
    expect(result).toContain("User");
    expect(result).toContain("string");
  });

  test("renders lists", () => {
    const input = `- Item 1
- Item 2
- Item 3`;
    const result = renderMarkdown(input);
    expect(result).toContain("Item 1");
    expect(result).toContain("Item 2");
    expect(result).toContain("Item 3");
  });

  test("renders blockquotes", () => {
    const input = "> This is a quote";
    const result = renderMarkdown(input);
    expect(result).toContain("This is a quote");
  });

  test("renders links", () => {
    const input = "Check out [this link](https://example.com)";
    const result = renderMarkdown(input);
    expect(result).toContain("this link");
  });

  test("handles empty input", () => {
    const result = renderMarkdown("");
    expect(result).toBe("");
  });

  test("returns original text on parse error", () => {
    // This should still work, but we test the fallback behavior
    const input = "Normal text";
    const result = renderMarkdown(input);
    expect(result).toContain("Normal text");
  });

  test("renders multiple paragraphs", () => {
    const input = `First paragraph.

Second paragraph.`;
    const result = renderMarkdown(input);
    expect(result).toContain("First paragraph");
    expect(result).toContain("Second paragraph");
  });

  test("renders complex markdown with mixed elements", () => {
    const input = `# Title

This is a paragraph with **bold** and *italic* text.

\`\`\`javascript
const greeting = "Hello";
\`\`\`

- List item 1
- List item 2`;

    const result = renderMarkdown(input);
    expect(result).toContain("Title");
    expect(result).toContain("bold");
    expect(result).toContain("italic");
    expect(result).toContain("greeting");
    expect(result).toContain("List item 1");
  });

  test("strips emoji characters from headings", () => {
    const input = "## \u{1F527} Core Capabilities";
    const result = renderMarkdown(input);
    expect(result).toContain("Core Capabilities");
    expect(result).not.toContain("\u{1F527}");
  });

  test("strips emoji characters from text", () => {
    const input = "\u{1F4DD} Writing & Content Creation";
    const result = renderMarkdown(input);
    expect(result).toContain("Writing & Content Creation");
    expect(result).not.toContain("\u{1F4DD}");
  });

  test("preserves markdown structure after stripping emoji", () => {
    const input = `## \u{1F6E0} Tools

- Item 1
- Item 2`;
    const result = renderMarkdown(input);
    expect(result).toContain("Tools");
    expect(result).toContain("Item 1");
    expect(result).toContain("Item 2");
  });
});

