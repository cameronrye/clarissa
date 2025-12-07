import { test, expect, describe } from "bun:test";
import { extractCodeBlocks, restoreCodeBlocks } from "./enhance.ts";

describe("extractCodeBlocks", () => {
  test("returns original text when no code blocks present", () => {
    const input = "This is a simple prompt without code.";
    const result = extractCodeBlocks(input);

    expect(result.text).toBe(input);
    expect(result.blocks).toHaveLength(0);
  });

  test("extracts single code block", () => {
    const input = "Check this code:\n```javascript\nconst x = 1;\n```\nWhat does it do?";
    const result = extractCodeBlocks(input);

    expect(result.blocks).toHaveLength(1);
    expect(result.blocks[0]).toBe("```javascript\nconst x = 1;\n```");
    expect(result.text).toContain("___CODE_BLOCK_0___");
    expect(result.text).not.toContain("```");
  });

  test("extracts multiple code blocks", () => {
    const input = `First block:
\`\`\`python
print("hello")
\`\`\`
Second block:
\`\`\`typescript
console.log("world");
\`\`\`
End.`;
    const result = extractCodeBlocks(input);

    expect(result.blocks).toHaveLength(2);
    expect(result.blocks[0]).toContain("python");
    expect(result.blocks[1]).toContain("typescript");
    expect(result.text).toContain("___CODE_BLOCK_0___");
    expect(result.text).toContain("___CODE_BLOCK_1___");
  });

  test("handles code block without language specifier", () => {
    const input = "Here:\n```\nsome code\n```\nDone.";
    const result = extractCodeBlocks(input);

    expect(result.blocks).toHaveLength(1);
    expect(result.blocks[0]).toBe("```\nsome code\n```");
  });

  test("handles empty code block", () => {
    const input = "Empty block:\n```\n```\nEnd.";
    const result = extractCodeBlocks(input);

    expect(result.blocks).toHaveLength(1);
    expect(result.blocks[0]).toBe("```\n```");
  });

  test("handles code block with special characters", () => {
    const input = '```json\n{"key": "value", "arr": [1, 2, 3]}\n```';
    const result = extractCodeBlocks(input);

    expect(result.blocks).toHaveLength(1);
    expect(result.blocks[0]).toContain('"key"');
  });

  test("preserves text around code blocks", () => {
    const input = "Before code.\n```\ncode\n```\nAfter code.";
    const result = extractCodeBlocks(input);

    expect(result.text).toContain("Before code.");
    expect(result.text).toContain("After code.");
  });
});

describe("restoreCodeBlocks", () => {
  test("returns original text when no blocks to restore", () => {
    const text = "Simple text without placeholders.";
    const result = restoreCodeBlocks(text, []);

    expect(result).toBe(text);
  });

  test("restores single code block", () => {
    const text = "Check this:\n___CODE_BLOCK_0___\nDone.";
    const blocks = ["```js\nconst x = 1;\n```"];
    const result = restoreCodeBlocks(text, blocks);

    expect(result).toBe("Check this:\n```js\nconst x = 1;\n```\nDone.");
  });

  test("restores multiple code blocks in order", () => {
    const text = "First: ___CODE_BLOCK_0___ Second: ___CODE_BLOCK_1___";
    const blocks = ["```a```", "```b```"];
    const result = restoreCodeBlocks(text, blocks);

    expect(result).toBe("First: ```a``` Second: ```b```");
  });

  test("handles missing placeholder gracefully", () => {
    const text = "No placeholder here.";
    const blocks = ["```code```"];
    const result = restoreCodeBlocks(text, blocks);

    expect(result).toBe(text);
  });

  test("roundtrip: extract then restore returns original", () => {
    const original = `Here is some code:
\`\`\`python
def hello():
    print("Hello, World!")
\`\`\`
And more text here.
\`\`\`javascript
const fn = () => "test";
\`\`\`
The end.`;

    const { text, blocks } = extractCodeBlocks(original);
    const restored = restoreCodeBlocks(text, blocks);

    expect(restored).toBe(original);
  });

  test("roundtrip with complex nested content", () => {
    const original = `Fix this bug:
\`\`\`typescript
function process(data: { items: string[] }) {
  return data.items.map(item => \`Result: \${item}\`);
}
\`\`\`
It throws an error when data is null.`;

    const { text, blocks } = extractCodeBlocks(original);
    const restored = restoreCodeBlocks(text, blocks);

    expect(restored).toBe(original);
  });
});

