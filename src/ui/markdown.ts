import { Marked } from "marked";
import { markedTerminal } from "marked-terminal";
import chalk from "chalk";

// Regex to match emoji characters and their modifiers (covers most common ranges)
// Includes: emoji, variation selectors, skin tone modifiers, zero-width joiners, etc.
const emojiRegex =
  /[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}\u{1F000}-\u{1F02F}\u{1F0A0}-\u{1F0FF}\u{1F100}-\u{1F1FF}\u{FE00}-\u{FE0F}\u{1F3FB}-\u{1F3FF}\u{200D}\u{20E3}]/gu;

/**
 * Strip emoji characters from text
 */
function stripEmoji(text: string): string {
  // Remove emoji and clean up resulting double spaces (but preserve newlines)
  return text.replace(emojiRegex, "").replace(/ {2,}/g, " ");
}

// Configure marked-terminal with syntax highlighting options
const marked = new Marked(
  markedTerminal({
    // Styling options
    code: chalk.bgGray.white,
    codespan: chalk.cyan,
    blockquote: chalk.gray.italic,
    strong: chalk.bold,
    em: chalk.italic,
    del: chalk.strikethrough,
    heading: chalk.bold.cyan,
    hr: chalk.gray,
    listitem: chalk.white,
    table: chalk.white,
    link: chalk.blue.underline,
    // Disable emoji conversion for cleaner output
    emoji: false,
    // Tab size for code blocks
    tab: 2,
  })
);

/**
 * Render markdown to terminal-formatted text with syntax highlighting
 */
export function renderMarkdown(text: string): string {
  try {
    // Strip emoji before parsing
    const cleaned = stripEmoji(text);
    // Parse and render markdown
    const rendered = marked.parse(cleaned);
    if (typeof rendered === "string") {
      return rendered.trim();
    }
    return cleaned;
  } catch {
    // If parsing fails, return cleaned text
    return stripEmoji(text);
  }
}

