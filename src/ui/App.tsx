import { useState, useCallback, useEffect, useRef } from "react";
import { Box, Text, useApp, useInput } from "ink";
import { Spinner, ConfirmInput, Alert } from "@inkjs/ui";
import { Agent } from "../agent.ts";
import { agentConfig } from "../config/index.ts";
import { sessionManager, type Session } from "../session/index.ts";
import { usageTracker } from "../llm/client.ts";
import { mcpClient } from "../mcp/index.ts";
import { toolRegistry } from "../tools/index.ts";
import { renderMarkdown } from "./markdown.ts";
import { contextManager } from "../llm/context.ts";
import { EnhancedTextInput } from "./components/EnhancedTextInput.tsx";
import { ErrorBoundary } from "./components/ErrorBoundary.tsx";
import { InteractiveSelect, type SelectOption } from "./components/InteractiveSelect.tsx";
import { providerRegistry } from "../llm/providers/index.ts";
import { runUpgrade } from "../update.ts";
import { dispatchCommand, cleanupAndExit, type CommandContext } from "./commands.ts";
import { useTerminalFocus } from "./hooks/useTerminalFocus.ts";

type AppState = "idle" | "thinking" | "tool" | "streaming" | "confirming" | "enhancing" | "upgradeConfirm" | "selecting";

type SelectionType = "provider" | "model" | "session" | null;

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

// All available slash commands for tab completion
const SLASH_COMMANDS = [
  "/help",
  "/clear",
  "/new",
  "/save",
  "/sessions",
  "/load",
  "/last",
  "/delete",
  "/remember",
  "/memories",
  "/forget",
  "/model",
  "/provider",
  "/mcp",
  "/tools",
  "/context",
  "/yolo",
  "/version",
  "/upgrade",
  "/exit",
  "/quit",
];

interface AppProps {
  initialSession?: Session;
}

export function App({ initialSession }: AppProps = {}) {
  const { exit } = useApp();
  const [state, setState] = useState<AppState>("idle");
  const [inputKey, setInputKey] = useState(0);
  const [messages, setMessages] = useState<Array<{ role: string; content: string }>>([]);
  const [streamContent, setStreamContent] = useState("");
  const [currentTool, setCurrentTool] = useState<ToolExecution | null>(null);
  const [pendingConfirmation, setPendingConfirmation] = useState<PendingConfirmation | null>(null);
  const [inputValue, setInputValue] = useState("");
  const [showCommandHints, setShowCommandHints] = useState(false);
  const [upgradeInfo, setUpgradeInfo] = useState<{ current: string; latest: string } | null>(null);
  const [selectionType, setSelectionType] = useState<SelectionType>(null);
  const [selectionOptions, setSelectionOptions] = useState<SelectOption[]>([]);
  const [selectionTitle, setSelectionTitle] = useState<string>("");
  const sessionLoadedRef = useRef(false);

  // Enable terminal focus reporting to fix visual bug where content
  // disappears when terminal loses focus
  useTerminalFocus();

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

  const handleUpgradeConfirmation = useCallback(async (confirmed: boolean) => {
    if (!upgradeInfo) {
      setState("idle");
      return;
    }
    if (confirmed) {
      setMessages((prev) => [...prev, { role: "system", content: "Starting upgrade... (this will exit Clarissa)" }]);
      setUpgradeInfo(null);
      setState("idle");
      // Run upgrade in next tick so message is displayed
      setTimeout(async () => {
        await runUpgrade();
        exit();
      }, 100);
    } else {
      setMessages((prev) => [...prev, { role: "system", content: "Upgrade cancelled" }]);
      setUpgradeInfo(null);
      setState("idle");
    }
  }, [upgradeInfo, exit]);

  const handleSelectionCancel = useCallback(() => {
    setSelectionType(null);
    setSelectionOptions([]);
    setSelectionTitle("");
    setState("idle");
  }, []);

  const handleSelectionComplete = useCallback(async (value: string) => {
    const type = selectionType;
    setSelectionType(null);
    setSelectionOptions([]);
    setSelectionTitle("");
    setState("idle");

    // Build a minimal command context for selection completions
    const ctx: CommandContext = {
      agent,
      addMessage: (role, content) => setMessages((prev) => [...prev, { role, content }]),
      clearMessages: () => setMessages([]),
      setDisplayMessages: (msgs) => setMessages(msgs),
      setState: (s) => setState(s as AppState),
      exit,
      showSelection: () => {},
      setUpgradeInfo,
    };

    if (type === "provider") {
      await dispatchCommand(`/provider ${value}`, ctx);
    } else if (type === "model") {
      await dispatchCommand(`/model ${value}`, ctx);
    } else if (type === "session") {
      await dispatchCommand(`/load ${value}`, ctx);
    }
  }, [selectionType, agent, exit]);

  // Load initial session if provided
  useEffect(() => {
    if (initialSession && !sessionLoadedRef.current) {
      sessionLoadedRef.current = true;
      agent.loadMessages(initialSession.messages);
      const displayMessages = initialSession.messages
        .filter((m) => m.role === "user" || m.role === "assistant")
        .map((m) => ({ role: m.role, content: m.content || "" }));
      setMessages([...displayMessages, { role: "system", content: `Resumed session: ${initialSession.name}` }]);
    }
  }, [initialSession, agent]);

  // Initialize context manager with active provider's model on startup
  useEffect(() => {
    const initContextForProvider = async () => {
      try {
        const provider = await providerRegistry.getActiveProvider();
        const providerModel = provider.info.availableModels?.[0] ?? provider.info.id;
        contextManager.setModel(providerModel);
        usageTracker.setModel(providerModel);
      } catch {
        // No provider available yet, will be set when provider is activated
      }
    };

    initContextForProvider();
  }, []);

  // Load configured MCP servers on startup
  useEffect(() => {
    const loadMcpServers = async () => {
      const configuredServers = mcpClient.getConfiguredServers();
      if (Object.keys(configuredServers).length === 0) return;

      const results = await mcpClient.loadConfiguredServers();
      const successful = results.filter(r => !r.error);
      const failed = results.filter(r => r.error);

      for (const result of successful) {
        toolRegistry.registerMany(result.tools);
      }

      if (successful.length > 0 || failed.length > 0) {
        let content = "";
        if (successful.length > 0) {
          const totalTools = successful.reduce((sum, r) => sum + r.tools.length, 0);
          content += `Loaded ${successful.length} MCP server${successful.length > 1 ? "s" : ""} (${totalTools} tools)`;
        }
        if (failed.length > 0) {
          if (content) content += "\n";
          content += `Failed to load: ${failed.map(f => `${f.name} (${f.error})`).join(", ")}`;
        }
        setMessages(prev => [...prev, { role: "system", content }]);
      }
    };

    loadMcpServers();
  }, []);

  // Clear input by incrementing key to force re-mount
  const clearInput = useCallback(() => {
    setInputKey((k) => k + 1);
  }, []);

  const handleSubmit = useCallback(
    async (value: string) => {
      if (!value.trim()) return;

      // Build command context for the dispatcher
      const ctx: CommandContext = {
        agent,
        addMessage: (role, content) => setMessages((prev) => [...prev, { role, content }]),
        clearMessages: () => setMessages([]),
        setDisplayMessages: (msgs) => setMessages(msgs),
        setState: (s) => setState(s as AppState),
        exit,
        showSelection: (type, title, options) => {
          setSelectionType(type);
          setSelectionOptions(options);
          setSelectionTitle(title);
          setState("selecting");
        },
        setUpgradeInfo,
      };

      // Try to dispatch as a slash command
      const result = await dispatchCommand(value, ctx);
      if (result === "handled") {
        clearInput();
        return;
      }

      // Not a command - send to the agent
      setMessages((prev) => [...prev, { role: "user", content: value }]);
      clearInput();
      setStreamContent("");
      setCurrentTool(null);

      try {
        const response = await agent.run(value);
        setMessages((prev) => [...prev, { role: "assistant", content: response }]);
        setStreamContent("");

        // Auto-save session after each message exchange
        if (!sessionManager.getCurrent()) {
          await sessionManager.create();
        }
        sessionManager.updateMessages(agent.getMessagesForSave());
        await sessionManager.save();
      } catch (error) {
        const msg = error instanceof Error ? error.message : "Unknown error";
        setMessages((prev) => [...prev, { role: "error", content: msg }]);
      }
      setState("idle");
    },
    [agent, exit, clearInput]
  );

  // Handle Ctrl+C - uses shared cleanup logic
  useInput((input, key) => {
    if (key.ctrl && input === "c") {
      cleanupAndExit(agent, exit);
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

      {state === "upgradeConfirm" && upgradeInfo && (
        <Box flexDirection="column" marginBottom={1} borderStyle="round" borderColor="cyan" padding={1}>
          <Box marginBottom={1}>
            <Text color="cyan" bold>Upgrade Clarissa?</Text>
          </Box>
          <Box marginBottom={1}>
            <Text>Current version: </Text>
            <Text color="gray">{upgradeInfo.current}</Text>
          </Box>
          <Box marginBottom={1}>
            <Text>Latest version: </Text>
            <Text color="green" bold>{upgradeInfo.latest}</Text>
          </Box>
          <Box>
            <Text color="gray">Proceed with upgrade? </Text>
            <ConfirmInput
              defaultChoice="confirm"
              onConfirm={() => handleUpgradeConfirmation(true)}
              onCancel={() => handleUpgradeConfirmation(false)}
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

      {state === "selecting" && selectionOptions.length > 0 && (
        <Box marginBottom={1}>
          <InteractiveSelect
            title={selectionTitle}
            options={selectionOptions}
            onSelect={handleSelectionComplete}
            onCancel={handleSelectionCancel}
          />
        </Box>
      )}

      {/* Command hints */}
      {showCommandHints && inputValue.startsWith("/") && (
        <Box marginBottom={1}>
          <Text color="gray">Commands: </Text>
          <Text color="cyan">
            {SLASH_COMMANDS.filter((cmd) =>
              cmd.toLowerCase().startsWith(inputValue.toLowerCase())
            )
              .slice(0, 8)
              .join(", ")}
          </Text>
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
          onChange={(value) => {
            setInputValue(value);
            setShowCommandHints(value.startsWith("/") && value.length > 0 && value.length < 10);
          }}
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

/**
 * App component with initial session (for --continue flag)
 */
export function AppWithSession({ initialSession }: { initialSession: Session }) {
  return (
    <ErrorBoundary>
      <App initialSession={initialSession} />
    </ErrorBoundary>
  );
}
