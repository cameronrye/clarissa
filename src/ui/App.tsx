import { useState, useCallback } from "react";
import { Box, Text, useApp, useInput } from "ink";
import { Spinner, ConfirmInput, Alert } from "@inkjs/ui";
import { Agent } from "../agent.ts";
import { agentConfig, AVAILABLE_MODELS } from "../config/index.ts";
import { sessionManager } from "../session/index.ts";
import { memoryManager } from "../memory/index.ts";
import { usageTracker } from "../llm/client.ts";
import { mcpClient } from "../mcp/index.ts";
import { toolRegistry } from "../tools/index.ts";
import { renderMarkdown } from "./markdown.ts";
import { contextManager } from "../llm/context.ts";
import { EnhancedTextInput } from "./components/EnhancedTextInput.tsx";
import { ErrorBoundary } from "./components/ErrorBoundary.tsx";

type AppState = "idle" | "thinking" | "tool" | "streaming" | "confirming" | "enhancing";

interface ToolExecution {
  name: string;
  args: string;
  result?: string;
}

interface PendingConfirmation {
  name: string;
  args: string;
  resolve: (confirmed: boolean) => void;
}

export function App() {
  const { exit } = useApp();
  const [state, setState] = useState<AppState>("idle");
  const [inputKey, setInputKey] = useState(0);
  const [messages, setMessages] = useState<Array<{ role: string; content: string }>>([]);
  const [streamContent, setStreamContent] = useState("");
  const [currentTool, setCurrentTool] = useState<ToolExecution | null>(null);
  const [pendingConfirmation, setPendingConfirmation] = useState<PendingConfirmation | null>(null);

  const [agent] = useState(
    () =>
      new Agent({
        onThinking: () => setState("thinking"),
        onToolCall: (name, args) => {
          setState("tool");
          setCurrentTool({ name, args });
        },
        onToolConfirmation: (name, args) => {
          return new Promise<boolean>((resolve) => {
            setState("confirming");
            setPendingConfirmation({ name, args, resolve });
          });
        },
        onToolResult: (_name, result) => {
          setCurrentTool((prev) => (prev ? { ...prev, result } : null));
        },
        onStreamChunk: (chunk) => {
          setState("streaming");
          setStreamContent((prev) => prev + chunk);
        },
        onResponse: () => {
          setState("idle");
        },
        onError: (error) => {
          setMessages((prev) => [...prev, { role: "error", content: error.message }]);
          setState("idle");
        },
      })
  );

  const handleConfirmation = useCallback((confirmed: boolean) => {
    if (pendingConfirmation) {
      pendingConfirmation.resolve(confirmed);
      setPendingConfirmation(null);
      setState("tool");
    }
  }, [pendingConfirmation]);

  // Clear input by incrementing key to force re-mount
  const clearInput = useCallback(() => {
    setInputKey((k) => k + 1);
  }, []);

  const handleSubmit = useCallback(
    async (value: string) => {
      if (!value.trim()) return;

      // Handle special commands
      if (value.toLowerCase() === "/exit" || value.toLowerCase() === "/quit") {
        exit();
        return;
      }

      if (value.toLowerCase() === "/clear") {
        setMessages([]);
        agent.reset();
        clearInput();
        return;
      }

      if (value.toLowerCase() === "/help") {
        setMessages((prev) => [
          ...prev,
          {
            role: "system",
            content: `Commands:
  /help             - Show this help
  /clear            - Clear conversation
  /save             - Save current session
  /sessions         - List saved sessions
  /load ID          - Load a saved session
  /delete ID        - Delete a saved session
  /remember <fact>  - Save a memory
  /memories         - List saved memories
  /forget <#|ID>    - Forget a memory
  /model [NAME]     - Show or switch model
  /mcp CMD ARGS     - Connect to MCP server
  /tools            - List available tools
  /context          - Show context window usage
  /yolo             - Toggle auto-approve mode
  /exit             - Exit Clarissa

Keyboard Shortcuts:
  Ctrl+P            - Enhance current prompt (make it clearer, fix errors)`,
          },
        ]);
        clearInput();
        return;
      }

      if (value.toLowerCase() === "/yolo") {
        const enabled = agentConfig.toggleAutoApprove();
        setMessages((prev) => [
          ...prev,
          {
            role: "system",
            content: enabled
              ? "Auto-approve enabled. Tool executions will no longer require confirmation."
              : "Auto-approve disabled. Tool executions will require confirmation.",
          },
        ]);
        clearInput();
        return;
      }

      if (value.toLowerCase() === "/model" || value.toLowerCase().startsWith("/model ")) {
        const parts = value.split(" ");
        if (parts.length === 1) {
          // Show current model and available models
          setMessages((prev) => [
            ...prev,
            {
              role: "system",
              content: `Current model: ${agentConfig.model}\n\nAvailable models:\n${AVAILABLE_MODELS.map((m) => `  - ${m}`).join("\n")}`,
            },
          ]);
        } else {
          const newModel = parts.slice(1).join(" ");
          // Validate model name
          if (!(AVAILABLE_MODELS as readonly string[]).includes(newModel)) {
            setMessages((prev) => [
              ...prev,
              {
                role: "error",
                content: `Unknown model: ${newModel}\n\nAvailable models:\n${AVAILABLE_MODELS.map((m) => `  - ${m}`).join("\n")}`,
              },
            ]);
            clearInput();
            return;
          }
          agentConfig.setModel(newModel);
          contextManager.setModel(newModel);
          usageTracker.setModel(newModel);
          setMessages((prev) => [...prev, { role: "system", content: `Model switched to: ${newModel}` }]);
        }
        clearInput();
        return;
      }

      if (value.toLowerCase() === "/save") {
        try {
          const current = sessionManager.getCurrent();
          if (!current) {
            await sessionManager.create();
          }
          sessionManager.updateMessages(agent.getMessagesForSave());
          await sessionManager.save();
          setMessages((prev) => [
            ...prev,
            { role: "system", content: `Session saved: ${sessionManager.getCurrent()?.name}` },
          ]);
        } catch (error) {
          const msg = error instanceof Error ? error.message : "Save failed";
          setMessages((prev) => [...prev, { role: "error", content: msg }]);
        }
        clearInput();
        return;
      }

      if (value.toLowerCase() === "/sessions") {
        try {
          const sessions = await sessionManager.list();
          if (sessions.length === 0) {
            setMessages((prev) => [...prev, { role: "system", content: "No saved sessions" }]);
          } else {
            const list = sessions
              .map((s) => `  ${s.id.slice(0, 20)}... - ${s.name} (${new Date(s.updatedAt).toLocaleDateString()})`)
              .join("\n");
            setMessages((prev) => [...prev, { role: "system", content: `Saved sessions:\n${list}` }]);
          }
        } catch (error) {
          const msg = error instanceof Error ? error.message : "List failed";
          setMessages((prev) => [...prev, { role: "error", content: msg }]);
        }
        clearInput();
        return;
      }

      if (value.toLowerCase().startsWith("/load ")) {
        const sessionId = value.slice(6).trim();
        try {
          const session = await sessionManager.load(sessionId);
          if (session) {
            agent.loadMessages(session.messages);
            // Convert saved messages to display format
            const displayMessages = session.messages
              .filter((m) => m.role === "user" || m.role === "assistant")
              .map((m) => ({ role: m.role, content: m.content || "" }));
            setMessages(displayMessages);
            setMessages((prev) => [...prev, { role: "system", content: `Loaded session: ${session.name}` }]);
          } else {
            setMessages((prev) => [...prev, { role: "error", content: `Session not found: ${sessionId}` }]);
          }
        } catch (error) {
          const msg = error instanceof Error ? error.message : "Load failed";
          setMessages((prev) => [...prev, { role: "error", content: msg }]);
        }
        clearInput();
        return;
      }

      if (value.toLowerCase().startsWith("/delete ")) {
        const sessionId = value.slice(8).trim();
        if (!sessionId) {
          setMessages((prev) => [...prev, { role: "error", content: "Usage: /delete <session_id>" }]);
          clearInput();
          return;
        }
        try {
          const deleted = await sessionManager.delete(sessionId);
          if (deleted) {
            setMessages((prev) => [...prev, { role: "system", content: `Deleted session: ${sessionId}` }]);
          } else {
            setMessages((prev) => [...prev, { role: "error", content: `Session not found: ${sessionId}` }]);
          }
        } catch (error) {
          const msg = error instanceof Error ? error.message : "Delete failed";
          setMessages((prev) => [...prev, { role: "error", content: msg }]);
        }
        clearInput();
        return;
      }

      if (value.toLowerCase().startsWith("/mcp ")) {
        const parts = value.slice(5).trim().split(" ");
        const command = parts[0];
        const args = parts.slice(1);

        if (!command) {
          setMessages((prev) => [...prev, { role: "error", content: "Usage: /mcp <command> [args...]" }]);
          clearInput();
          return;
        }

        try {
          setState("thinking");
          const serverName = command.replace(/[^a-zA-Z0-9]/g, "_");
          const tools = await mcpClient.connect({ name: serverName, command, args });
          toolRegistry.registerMany(tools);
          setMessages((prev) => [
            ...prev,
            { role: "system", content: `Connected to MCP server: ${serverName}\nRegistered ${tools.length} tools: ${tools.map((t) => t.name).join(", ")}` },
          ]);
        } catch (error) {
          const msg = error instanceof Error ? error.message : "MCP connection failed";
          setMessages((prev) => [...prev, { role: "error", content: msg }]);
        }
        setState("idle");
        clearInput();
        return;
      }

      if (value.toLowerCase() === "/tools") {
        const tools = toolRegistry.getToolNames();
        const mcpTools = toolRegistry.getByCategory("mcp");
        setMessages((prev) => [
          ...prev,
          {
            role: "system",
            content: `Available tools (${tools.length}):\n${tools.map((t) => `  - ${t}${mcpTools.some((m) => m.name === t) ? " (MCP)" : ""}`).join("\n")}`,
          },
        ]);
        clearInput();
        return;
      }

      if (value.toLowerCase() === "/context") {
        const stats = contextManager.getDetailedStats(agent.getHistory());
        const barWidth = 40;
        const filledWidth = Math.round((stats.usagePercent / 100) * barWidth);
        const emptyWidth = barWidth - filledWidth;
        const bar = `[${"=".repeat(filledWidth)}${" ".repeat(emptyWidth)}]`;

        const formatTokens = (n: number) => n.toLocaleString().padStart(8);
        const formatPercent = (tokens: number, total: number) =>
          total > 0 ? `${Math.round((tokens / total) * 100)}%`.padStart(4) : "  0%";

        const { breakdown: b } = stats;
        const content = `Context Usage: ${stats.usagePercent}%
${bar} ${stats.totalTokens.toLocaleString()}/${stats.maxTokens.toLocaleString()} tokens

Model: ${stats.model}
Response Reserve: ${stats.responseReserve.toLocaleString()} tokens

Breakdown by type:
  System:    ${formatTokens(b.system.tokens)} tokens (${formatPercent(b.system.tokens, stats.totalTokens)}) - ${b.system.count} message(s)
  User:      ${formatTokens(b.user.tokens)} tokens (${formatPercent(b.user.tokens, stats.totalTokens)}) - ${b.user.count} message(s)
  Assistant: ${formatTokens(b.assistant.tokens)} tokens (${formatPercent(b.assistant.tokens, stats.totalTokens)}) - ${b.assistant.count} message(s)
  Tool:      ${formatTokens(b.tool.tokens)} tokens (${formatPercent(b.tool.tokens, stats.totalTokens)}) - ${b.tool.count} message(s)`;

        setMessages((prev) => [...prev, { role: "system", content }]);
        clearInput();
        return;
      }

      if (value.toLowerCase().startsWith("/remember ")) {
        const fact = value.slice(10).trim();
        if (!fact) {
          setMessages((prev) => [...prev, { role: "error", content: "Usage: /remember <fact>" }]);
          clearInput();
          return;
        }
        try {
          await memoryManager.add(fact);
          setMessages((prev) => [...prev, { role: "system", content: `Remembered: ${fact}` }]);
        } catch (error) {
          const msg = error instanceof Error ? error.message : "Failed to save memory";
          setMessages((prev) => [...prev, { role: "error", content: msg }]);
        }
        clearInput();
        return;
      }

      if (value.toLowerCase() === "/memories") {
        try {
          const memories = await memoryManager.list();
          if (memories.length === 0) {
            setMessages((prev) => [...prev, { role: "system", content: "No saved memories" }]);
          } else {
            const list = memories
              .map((m, i) => `  ${i + 1}. ${m.content}`)
              .join("\n");
            setMessages((prev) => [
              ...prev,
              { role: "system", content: `Memories (${memories.length}):\n${list}\n\nUse /forget <#> to remove a memory` },
            ]);
          }
        } catch (error) {
          const msg = error instanceof Error ? error.message : "Failed to list memories";
          setMessages((prev) => [...prev, { role: "error", content: msg }]);
        }
        clearInput();
        return;
      }

      if (value.toLowerCase().startsWith("/forget ")) {
        const idOrIndex = value.slice(8).trim();
        if (!idOrIndex) {
          setMessages((prev) => [...prev, { role: "error", content: "Usage: /forget <# or ID>" }]);
          clearInput();
          return;
        }
        try {
          const forgotten = await memoryManager.forget(idOrIndex);
          if (forgotten) {
            setMessages((prev) => [...prev, { role: "system", content: `Memory forgotten` }]);
          } else {
            setMessages((prev) => [...prev, { role: "error", content: `Memory not found: ${idOrIndex}` }]);
          }
        } catch (error) {
          const msg = error instanceof Error ? error.message : "Failed to forget memory";
          setMessages((prev) => [...prev, { role: "error", content: msg }]);
        }
        clearInput();
        return;
      }

      // Add user message and clear input immediately
      setMessages((prev) => [...prev, { role: "user", content: value }]);
      clearInput();
      setStreamContent("");
      setCurrentTool(null);

      try {
        const response = await agent.run(value);
        setMessages((prev) => [...prev, { role: "assistant", content: response }]);
        setStreamContent("");
      } catch (error) {
        const msg = error instanceof Error ? error.message : "Unknown error";
        setMessages((prev) => [...prev, { role: "error", content: msg }]);
      }
      setState("idle");
    },
    [agent, exit, clearInput]
  );

  // Handle Ctrl+C
  useInput((input, key) => {
    if (key.ctrl && input === "c") {
      exit();
    }
  });

  return (
    <Box flexDirection="column" padding={1}>
      {/* Header */}
      <Box marginBottom={1} justifyContent="space-between">
        <Box>
          <Text bold color="cyan">
            ✨ {agentConfig.appName}
          </Text>
          <Text color="gray"> - AI Assistant (type /help for commands)</Text>
        </Box>
        <Box>
          <Text color="gray" dimColor>
            {usageTracker.formatUsage()}
          </Text>
        </Box>
      </Box>

      {/* Message History */}
      <Box flexDirection="column" marginBottom={1}>
        {messages.map((msg, i) => (
          <MessageBubble key={i} role={msg.role} content={msg.content} />
        ))}
      </Box>

      {/* Current Activity */}
      {state === "thinking" && (
        <Box marginBottom={1}>
          <Spinner label="Thinking..." />
        </Box>
      )}

      {state === "confirming" && pendingConfirmation && (
        <Box flexDirection="column" marginBottom={1} borderStyle="round" borderColor="yellow" padding={1}>
          <Box marginBottom={1}>
            <Text color="yellow" bold>Confirm tool execution:</Text>
          </Box>
          <Box marginBottom={1}>
            <Text color="white" bold>{pendingConfirmation.name}</Text>
          </Box>
          <Box marginBottom={1}>
            <Text color="gray">{formatArgs(pendingConfirmation.args)}</Text>
          </Box>
          <Box>
            <Text color="gray">Allow this action? </Text>
            <ConfirmInput
              defaultChoice="confirm"
              onConfirm={() => handleConfirmation(true)}
              onCancel={() => handleConfirmation(false)}
            />
          </Box>
        </Box>
      )}

      {state === "tool" && currentTool && (
        <Box flexDirection="column" marginBottom={1}>
          <Box>
            <Text color="yellow">🔧 Using tool: </Text>
            <Text bold>{currentTool.name}</Text>
          </Box>
          {currentTool.result && (
            <Box marginLeft={2}>
              <Text color="gray">{truncate(currentTool.result, 200)}</Text>
            </Box>
          )}
        </Box>
      )}

      {state === "streaming" && streamContent && (
        <Box marginBottom={1}>
          <Text color="green">▸ </Text>
          <Text>{streamContent}</Text>
          <Text color="cyan">▌</Text>
        </Box>
      )}

      {state === "enhancing" && (
        <Box marginBottom={1}>
          <Spinner label="Enhancing prompt..." />
        </Box>
      )}

      {/* Input */}
      <Box>
        <Text color="magenta" bold>
          {"❯ "}
        </Text>
        <EnhancedTextInput
          key={inputKey}
          placeholder="Ask Clarissa anything... (Ctrl+P to enhance)"
          onSubmit={handleSubmit}
          isDisabled={state !== "idle" && state !== "enhancing"}
          onEnhanceStart={() => setState("enhancing")}
          onEnhanceComplete={() => setState("idle")}
          onEnhanceError={(error) => {
            setMessages((prev) => [
              ...prev,
              { role: "error", content: `Enhancement failed: ${error.message}` },
            ]);
            setState("idle");
          }}
        />
      </Box>
    </Box>
  );
}

function MessageBubble({ role, content }: { role: string; content: string }) {
  const colors: Record<string, string> = {
    user: "blue",
    assistant: "green",
    system: "gray",
    error: "red",
  };

  const prefixes: Record<string, string> = {
    user: "You",
    assistant: "Clarissa",
    system: "System",
    error: "Error",
  };

  // Render markdown for assistant messages
  const displayContent = role === "assistant" ? renderMarkdown(content) : content;

  // Use Alert component for error messages for better visibility
  if (role === "error") {
    return (
      <Box marginBottom={1}>
        <Alert variant="error" title="Error">
          {content}
        </Alert>
      </Box>
    );
  }

  return (
    <Box flexDirection="column" marginBottom={1}>
      <Text bold color={colors[role] || "white"}>
        {prefixes[role] || role}:
      </Text>
      <Box marginLeft={2}>
        <Text wrap="wrap">{displayContent}</Text>
      </Box>
    </Box>
  );
}

function truncate(str: string, maxLen: number): string {
  if (str.length <= maxLen) return str;
  return str.slice(0, maxLen) + "...";
}

function formatArgs(argsJson: string): string {
  try {
    const args = JSON.parse(argsJson);
    return Object.entries(args)
      .map(([key, value]) => {
        const strValue = typeof value === "string" ? value : JSON.stringify(value);
        return `  ${key}: ${truncate(strValue, 100)}`;
      })
      .join("\n");
  } catch {
    return truncate(argsJson, 200);
  }
}

/**
 * Wrapped App component with error boundary
 */
export function AppWithErrorBoundary() {
  return (
    <ErrorBoundary>
      <App />
    </ErrorBoundary>
  );
}

