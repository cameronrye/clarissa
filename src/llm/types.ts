/**
 * LLM Types for the Clarissa Agent
 */

export type MessageRole = "system" | "user" | "assistant" | "tool";

export interface Message {
  role: MessageRole;
  content: string | null;
  tool_calls?: ToolCall[];
  tool_call_id?: string;
  name?: string;
}

export interface ToolCall {
  id: string;
  type: "function";
  function: {
    name: string;
    arguments: string;
  };
}

export interface ToolResult {
  tool_call_id: string;
  role: "tool";
  content: string;
  name: string;
}

export interface ChatCompletionChoice {
  index: number;
  message: Message;
  finish_reason: string | null;
}

export interface ChatCompletionResponse {
  id: string;
  model: string;
  choices: ChatCompletionChoice[];
  usage?: {
    prompt_tokens: number;
    completion_tokens: number;
    total_tokens: number;
  };
}

export interface StreamChunk {
  id: string;
  model: string;
  choices: {
    index: number;
    delta: {
      role?: MessageRole;
      content?: string;
      tool_calls?: Partial<ToolCall>[];
    };
    finish_reason: string | null;
  }[];
}

/**
 * Tool definition for OpenRouter API
 */
export interface ToolDefinition {
  type: "function";
  function: {
    name: string;
    description: string;
    parameters: {
      type: "object";
      properties: Record<string, unknown>;
      required?: string[];
    };
  };
}

