import { llmClient } from "./client.ts";
import { agentConfig } from "../config/index.ts";
import type { Message } from "./types.ts";

/**
 * System prompt for the prompt enhancement feature.
 * Instructs the LLM to improve prompts while preserving intent and code blocks.
 */
const ENHANCEMENT_SYSTEM_PROMPT = `You are a prompt enhancement assistant. Your task is to improve user prompts to make them clearer, more specific, and more effective.

Guidelines for enhancement:
1. Make the prompt more detailed and explicit
2. Remove ambiguity and vague language
3. Fix grammatical or spelling errors
4. Add relevant context where it would help
5. Preserve the original intent completely
6. Keep the prompt concise - don't make it unnecessarily long
7. IMPORTANT: Preserve any code blocks (content between triple backticks \`\`\`) exactly as they are - do not modify code
8. Return ONLY the enhanced prompt, no explanations or preamble

If the prompt is already clear and well-formed, return it with minimal changes.`;

/**
 * Enhances a user prompt using the LLM to make it clearer and more specific.
 *
 * @param prompt - The original prompt text to enhance
 * @param onChunk - Optional callback for streaming chunks
 * @returns The enhanced prompt text
 */
export async function enhancePrompt(
  prompt: string,
  onChunk?: (chunk: string) => void
): Promise<string> {
  if (!prompt.trim()) {
    return prompt;
  }

  const messages: Message[] = [
    {
      role: "system",
      content: ENHANCEMENT_SYSTEM_PROMPT,
    },
    {
      role: "user",
      content: `Enhance this prompt:\n\n${prompt}`,
    },
  ];

  const response = await llmClient.chatStreamComplete(
    messages,
    undefined, // No tools needed for enhancement
    agentConfig.model,
    onChunk
  );

  return response.content || prompt;
}

/**
 * Extracts code blocks from text and replaces them with placeholders.
 * Used to preserve code during enhancement.
 */
export function extractCodeBlocks(
  text: string
): { text: string; blocks: string[] } {
  const blocks: string[] = [];
  const placeholder = "___CODE_BLOCK_";

  // Match code blocks with triple backticks
  const regex = /```[\s\S]*?```/g;
  let match;
  let result = text;
  let index = 0;

  while ((match = regex.exec(text)) !== null) {
    blocks.push(match[0]);
    result = result.replace(match[0], `${placeholder}${index}___`);
    index++;
  }

  return { text: result, blocks };
}

/**
 * Restores code blocks from placeholders.
 */
export function restoreCodeBlocks(text: string, blocks: string[]): string {
  let result = text;
  const placeholder = "___CODE_BLOCK_";

  for (let i = 0; i < blocks.length; i++) {
    const block = blocks[i];
    if (block !== undefined) {
      result = result.replace(`${placeholder}${i}___`, block);
    }
  }

  return result;
}

/**
 * Enhances a prompt while preserving code blocks exactly.
 * This extracts code blocks, enhances the rest, then restores them.
 *
 * @param prompt - The original prompt text
 * @param onChunk - Optional streaming callback
 * @returns The enhanced prompt with preserved code blocks
 */
export async function enhancePromptPreservingCode(
  prompt: string,
  onChunk?: (chunk: string) => void
): Promise<string> {
  const { text, blocks } = extractCodeBlocks(prompt);

  // If no code blocks, use standard enhancement
  if (blocks.length === 0) {
    return enhancePrompt(prompt, onChunk);
  }

  // Enhance text with placeholders
  const enhancedWithPlaceholders = await enhancePrompt(text, onChunk);

  // Restore the original code blocks
  return restoreCodeBlocks(enhancedWithPlaceholders, blocks);
}

