import { useState, useCallback, useEffect, useRef } from "react";
import { Box, Text, useApp, useInput } from "ink";
import { Spinner, ConfirmInput, Alert } from "@inkjs/ui";
import { Agent } from "../agent.ts";
import { agentConfig } from "../config/index.ts";
import { sessionManager, type Session } from "../session/index.ts";
import { memoryManager } from "../memory/index.ts";
import { usageTracker } from "../llm/client.ts";
import { mcpClient } from "../mcp/index.ts";
import { toolRegistry } from "../tools/index.ts";
import { renderMarkdown } from "./markdown.ts";
import { contextManager } from "../llm/context.ts";
import { EnhancedTextInput } from "./components/EnhancedTextInput.tsx";
import { ErrorBoundary } from "./components/ErrorBoundary.tsx";
import { InteractiveSelect, type SelectOption } from "./components/InteractiveSelect.tsx";
import { CURRENT_VERSION, runUpgrade, fetchLatestVersion, isNewerVersion } from "../update.ts";
import { providerRegistry, type ProviderId } from "../llm/providers/index.ts";
import { preferencesManager } from "../preferences/index.ts";
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

    if (type === "provider") {
      try {
        await providerRegistry.setActiveProvider(value as ProviderId);
        const provider = providerRegistry.getProvider(value as ProviderId);
        const providerModel = provider?.info.availableModels?.[0] ?? value;
        contextManager.setModel(providerModel);
        usageTracker.setModel(providerModel);
        await preferencesManager.setLastProvider(value as ProviderId);
        setMessages((prev) => [
          ...prev,
          { role: "system", content: `Provider switched to: ${provider?.info.name || value}` },
        ]);
      } catch (error) {
        const msg = error instanceof Error ? error.message : "Failed to switch provider";
        setMessages((prev) => [...prev, { role: "error", content: msg }]);
      }
    } else if (type === "model") {
      agentConfig.setModel(value);
      contextManager.setModel(value);
      usageTracker.setModel(value);
      setMessages((prev) => [
        ...prev,
        { role: "system", content: `Model switched to: ${value}` },
      ]);
    } else if (type === "session") {
      try {
        const session = await sessionManager.load(value);
        if (session) {
          agent.loadMessages(session.messages);
          const displayMessages = session.messages
            .filter((m) => m.role === "user" || m.role === "assistant")
            .map((m) => ({ role: m.role, content: m.content || "" }));
          setMessages([...displayMessages, { role: "system", content: `Loaded session: ${session.name}` }]);
        }
      } catch (error) {
        const msg = error instanceof Error ? error.message : "Failed to load session";
        setMessages((prev) => [...prev, { role: "error", content: msg }]);
      }
    }
  }, [selectionType, agent]);

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

  // Note: Session is saved explicitly in /exit and after each message exchange
  // We don't use a cleanup effect here since it can't await async operations

  // Initialize context manager with active provider's model on startup
  useEffect(() => {
    const initContextForProvider = async () => {
      try {
        const provider = await providerRegistry.getActiveProvider();
        // For providers with fixed models (like apple-ai), use the provider ID for context limits
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

      // Register tools from successful connections
      for (const result of successful) {
        toolRegistry.registerMany(result.tools);
      }

      // Show status message
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

      // Handle special commands
      if (value.toLowerCase() === "/exit" || value.toLowerCase() === "/quit") {
        // Save session before exit
        try {
          const history = agent.getMessagesForSave();
          if (history.length > 0) {
            if (!sessionManager.getCurrent()) {
              await sessionManager.create();
            }
            sessionManager.updateMessages(history);
            await sessionManager.save();
          }
        } catch {
          // Ignore save errors on exit
        }
        // Shutdown provider (unloads local-llama model if active)
        try {
          await providerRegistry.shutdown();
        } catch {
          // Ignore shutdown errors on exit
        }
        exit();
        // Force process exit after a short delay to ensure cleanup
        setTimeout(() => process.exit(0), 100);
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
  /new              - Start a new conversation
  /save             - Save current session
  /sessions         - List saved sessions
  /load ID          - Load a saved session
  /last             - Load most recent session
  /delete ID        - Delete a saved session
  /remember <fact>  - Save a memory
  /memories         - List saved memories
  /forget <#|ID>    - Forget a memory
  /model [NAME]     - Show or switch model
  /provider [NAME]  - Show or switch LLM provider
  /mcp              - Show MCP server status
  /mcp CMD ARGS     - Connect to stdio MCP server
  /mcp sse URL      - Connect to HTTP/SSE MCP server
  /tools            - List available tools
  /context          - Show context window usage
  /yolo             - Toggle auto-approve mode
  /version          - Show version info
  /upgrade          - Upgrade to latest version
  /exit             - Exit Clarissa

File References:
  @path/to/file.ext     - Include file contents in your message
  @file.txt:10-20       - Include lines 10-20 only

Keyboard Shortcuts:
  Esc Esc           - Clear current input
  Ctrl+P            - Enhance current prompt (make it clearer, fix errors)
  Tab               - Show command suggestions when typing /`,
          },
        ]);
        clearInput();
        return;
      }

      if (value.toLowerCase() === "/version") {
        setMessages((prev) => [
          ...prev,
          { role: "system", content: `Clarissa v${CURRENT_VERSION}` },
        ]);
        clearInput();
        return;
      }

      if (value.toLowerCase() === "/upgrade") {
        // Check if running in development mode (bun --hot)
        if (process.env.NODE_ENV === "development" || process.argv.includes("--hot")) {
          setMessages((prev) => [
            ...prev,
            { role: "system", content: "Upgrade not available in development mode.\nRun 'clarissa upgrade' from the command line instead." },
          ]);
          clearInput();
          return;
        }
        // Check for latest version
        setMessages((prev) => [...prev, { role: "system", content: "Checking for updates..." }]);
        clearInput();
        const latest = await fetchLatestVersion();
        if (!latest) {
          setMessages((prev) => [...prev, { role: "error", content: "Failed to check for updates. Please try again later." }]);
          return;
        }
        if (!isNewerVersion(CURRENT_VERSION, latest)) {
          setMessages((prev) => [...prev, { role: "system", content: `Already on latest version (${CURRENT_VERSION})` }]);
          return;
        }
        // Show version info and ask for confirmation
        setMessages((prev) => [
          ...prev,
          { role: "system", content: `Update available: ${CURRENT_VERSION} -> ${latest}` },
        ]);
        setUpgradeInfo({ current: CURRENT_VERSION, latest });
        setState("upgradeConfirm");
        return;
      }

      if (value.toLowerCase() === "/new") {
        setMessages([]);
        agent.reset();
        setMessages((prev) => [...prev, { role: "system", content: "Started new conversation" }]);
        clearInput();
        return;
      }

      if (value.toLowerCase() === "/last") {
        try {
          const session = await sessionManager.getLatest();
          if (session) {
            agent.loadMessages(session.messages);
            const displayMessages = session.messages
              .filter((m) => m.role === "user" || m.role === "assistant")
              .map((m) => ({ role: m.role, content: m.content || "" }));
            setMessages(displayMessages);
            setMessages((prev) => [...prev, { role: "system", content: `Loaded session: ${session.name}` }]);
          } else {
            setMessages((prev) => [...prev, { role: "system", content: "No saved sessions found" }]);
          }
        } catch (error) {
          const msg = error instanceof Error ? error.message : "Load failed";
          setMessages((prev) => [...prev, { role: "error", content: msg }]);
        }
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
        const availableModels = providerRegistry.getAvailableModels();
        const providerId = providerRegistry.getActiveProviderId();

        if (parts.length === 1) {
          // Show interactive model selector
          if (!availableModels || availableModels.length === 0) {
            setMessages((prev) => [
              ...prev,
              {
                role: "system",
                content: `Current model: ${agentConfig.model}\n\nThe ${providerId || "current"} provider uses a fixed or dynamically loaded model that cannot be changed via /model.`,
              },
            ]);
          } else {
            const options: SelectOption[] = availableModels.map((m) => ({
              label: m.split("/").pop() || m,
              value: m,
              hint: m === agentConfig.model ? "(current)" : undefined,
            }));
            setSelectionType("model");
            setSelectionOptions(options);
            setSelectionTitle(`Select model for ${providerId} (current: ${agentConfig.model.split("/").pop()})`);
            setState("selecting");
          }
        } else {
          const newModel = parts.slice(1).join(" ");

          if (!availableModels || availableModels.length === 0) {
            setMessages((prev) => [
              ...prev,
              {
                role: "error",
                content: `The ${providerId || "current"} provider uses a fixed or dynamically loaded model. Model selection is not available.\n\nUse /provider to switch to a different provider if you need to select a model.`,
              },
            ]);
            clearInput();
            return;
          }

          if (!availableModels.includes(newModel)) {
            setMessages((prev) => [
              ...prev,
              {
                role: "error",
                content: `Unknown model: ${newModel}\n\nAvailable models for ${providerId}:\n${availableModels.map((m) => `  - ${m}`).join("\n")}`,
              },
            ]);
            clearInput();
            return;
          }
          agentConfig.setModel(newModel);
          contextManager.setModel(newModel);
          usageTracker.setModel(newModel);
          await preferencesManager.setLastModel(newModel);
          setMessages((prev) => [...prev, { role: "system", content: `Model switched to: ${newModel}` }]);
        }
        clearInput();
        return;
      }

      if (value.toLowerCase() === "/provider" || value.toLowerCase().startsWith("/provider ")) {
        const parts = value.split(" ");
        if (parts.length === 1) {
          // Show interactive provider selector
          try {
            const statuses = await providerRegistry.getProviderStatuses();
            const registered = providerRegistry.getRegisteredProviders();
            const activeProvider = await providerRegistry.getActiveProvider().catch(() => null);
            const activeId = activeProvider?.info.id;

            // Build options for available providers only
            const options: SelectOption[] = [];
            for (const { id, name } of registered) {
              const status = statuses.get(id);
              if (status?.available) {
                const hint = id === activeId ? "(current)" : status.model ? `(${status.model})` : "";
                options.push({ label: `${id}: ${name}`, value: id, hint });
              }
            }

            if (options.length === 0) {
              setMessages((prev) => [...prev, { role: "error", content: "No providers available" }]);
            } else {
              setSelectionType("provider");
              setSelectionOptions(options);
              setSelectionTitle(`Select provider (current: ${activeId || "none"})`);
              setState("selecting");
            }
          } catch (error) {
            const msg = error instanceof Error ? error.message : "Failed to get provider status";
            setMessages((prev) => [...prev, { role: "error", content: msg }]);
          }
        } else {
          const newProvider = parts[1] as ProviderId;
          try {
            await providerRegistry.setActiveProvider(newProvider);
            const provider = providerRegistry.getProvider(newProvider);
            const providerModel = provider?.info.availableModels?.[0] ?? newProvider;
            contextManager.setModel(providerModel);
            usageTracker.setModel(providerModel);
            await preferencesManager.setLastProvider(newProvider);
            setMessages((prev) => [
              ...prev,
              { role: "system", content: `Provider switched to: ${provider?.info.name || newProvider}` },
            ]);
          } catch (error) {
            const msg = error instanceof Error ? error.message : "Failed to switch provider";
            setMessages((prev) => [...prev, { role: "error", content: msg }]);
          }
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
            const options: SelectOption[] = sessions.map((s) => ({
              label: s.name,
              value: s.id,
              hint: new Date(s.updatedAt).toLocaleDateString(),
            }));
            setSelectionType("session");
            setSelectionOptions(options);
            setSelectionTitle("Select session to load");
            setState("selecting");
          }
        } catch (error) {
          const msg = error instanceof Error ? error.message : "List failed";
          setMessages((prev) => [...prev, { role: "error", content: msg }]);
        }
        clearInput();
        return;
      }

      if (value.toLowerCase() === "/load" || value.toLowerCase().startsWith("/load ")) {
        const sessionId = value.slice(6).trim();
        if (!sessionId) {
          setMessages((prev) => [...prev, { role: "error", content: "Usage: /load <session_id>\nUse /sessions to list available sessions." }]);
          clearInput();
          return;
        }
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

      if (value.toLowerCase() === "/delete" || value.toLowerCase().startsWith("/delete ")) {
        const sessionId = value.slice(8).trim();
        if (!sessionId) {
          setMessages((prev) => [...prev, { role: "error", content: "Usage: /delete <session_id>\nUse /sessions to list available sessions." }]);
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

      if (value.toLowerCase() === "/mcp" || value.toLowerCase().startsWith("/mcp ")) {
        const mcpArgs = value.slice(5).trim();

        // No args - show MCP status
        if (!mcpArgs) {
          const connectedServers = mcpClient.getServerInfo();
          const configuredServers = mcpClient.getConfiguredServers();
          const configuredNames = Object.keys(configuredServers);

          let content = "MCP Servers:\n";

          if (connectedServers.length === 0 && configuredNames.length === 0) {
            content += "  No MCP servers configured.\n\n";
            content += "Usage:\n";
            content += "  /mcp sse <URL>           Connect to HTTP/SSE server\n";
            content += "  /mcp <CMD> [ARGS...]     Connect to stdio server\n\n";
            content += "Examples:\n";
            content += "  /mcp sse https://mcp.example.com/api\n";
            content += "  /mcp npx -y @modelcontextprotocol/server-filesystem /path\n\n";
            content += "Or add to ~/.clarissa/config.json:\n";
            content += '  {"mcpServers": {"name": {"command": "npx", "args": [...]}}}';
          } else {
            if (connectedServers.length > 0) {
              content += "\nConnected:\n";
              for (const server of connectedServers) {
                content += `  - ${server.name} (${server.toolCount} tools)\n`;
              }
            }

            const disconnected = configuredNames.filter(n => !connectedServers.some(s => s.name === n));
            if (disconnected.length > 0) {
              content += "\nConfigured (not connected):\n";
              for (const name of disconnected) {
                const cfg = configuredServers[name];
                if (cfg && "command" in cfg) {
                  content += `  - ${name}: ${cfg.command} ${cfg.args?.join(" ") || ""}\n`;
                } else if (cfg && "url" in cfg) {
                  content += `  - ${name}: ${cfg.url} (SSE)\n`;
                }
              }
            }
          }

          setMessages((prev) => [...prev, { role: "system", content }]);
          clearInput();
          return;
        }

        // Connect to an MCP server
        setState("thinking");
        setMessages((prev) => [...prev, { role: "user", content: value }]);
        clearInput();

        try {
          const parts = mcpArgs.split(/\s+/);

          // Check for SSE transport: /mcp sse <URL>
          if (parts[0]?.toLowerCase() === "sse" && parts[1]) {
            const url = parts[1];
            // Use URL hostname as server name
            const serverName = new URL(url).hostname.replace(/\./g, "-");

            setMessages((prev) => [...prev, { role: "system", content: `Connecting to SSE server: ${url}...` }]);

            const tools = await mcpClient.connectSse(serverName, url);

            // Register tools
            for (const tool of tools) {
              toolRegistry.register(tool);
            }

            setMessages((prev) => [...prev, {
              role: "system",
              content: `Connected to ${serverName} (SSE)\nRegistered ${tools.length} tool(s): ${tools.map(t => t.name).join(", ")}`
            }]);
          } else {
            // Stdio transport: /mcp <command> [args...]
            const command = parts[0]!;
            const cmdArgs = parts.slice(1);
            const serverName = command.replace(/[^a-zA-Z0-9]/g, "-");

            setMessages((prev) => [...prev, { role: "system", content: `Connecting to: ${command} ${cmdArgs.join(" ")}...` }]);

            const tools = await mcpClient.connect({
              name: serverName,
              command,
              args: cmdArgs,
            });

            // Register tools
            for (const tool of tools) {
              toolRegistry.register(tool);
            }

            setMessages((prev) => [...prev, {
              role: "system",
              content: `Connected to ${serverName}\nRegistered ${tools.length} tool(s): ${tools.map(t => t.name).join(", ")}`
            }]);
          }
        } catch (error) {
          const msg = error instanceof Error ? error.message : "Connection failed";
          setMessages((prev) => [...prev, { role: "error", content: `MCP connection failed: ${msg}` }]);
        }

        setState("idle");
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

      if (value.toLowerCase() === "/remember" || value.toLowerCase().startsWith("/remember ")) {
        const fact = value.slice(10).trim();
        if (!fact) {
          setMessages((prev) => [...prev, { role: "error", content: "Usage: /remember <fact>" }]);
          clearInput();
          return;
        }
        try {
          const memory = await memoryManager.add(fact);
          if (memory) {
            setMessages((prev) => [...prev, { role: "system", content: `Remembered: ${fact}` }]);
          } else {
            setMessages((prev) => [...prev, { role: "system", content: `Already remembered: ${fact}` }]);
          }
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

      if (value.toLowerCase() === "/forget" || value.toLowerCase().startsWith("/forget ")) {
        const idOrIndex = value.slice(8).trim();
        if (!idOrIndex) {
          setMessages((prev) => [...prev, { role: "error", content: "Usage: /forget <# or ID>\nUse /memories to list saved memories." }]);
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

      // Block unknown slash commands from being sent to LLM
      if (value.startsWith("/")) {
        const cmd = value.split(" ")[0]?.toLowerCase() || "";
        setMessages((prev) => [...prev, { role: "error", content: `Unknown command: ${cmd}\nType /help to see available commands.` }]);
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

  // Handle Ctrl+C - save session and cleanup before exit
  useInput((input, key) => {
    if (key.ctrl && input === "c") {
      // Cleanup asynchronously then exit
      (async () => {
        try {
          // Save session before exit
          const history = agent.getMessagesForSave();
          if (history.length > 0) {
            if (!sessionManager.getCurrent()) {
              await sessionManager.create();
            }
            sessionManager.updateMessages(history);
            await sessionManager.save();
          }
        } catch {
          // Ignore save errors on exit
        }
        try {
          // Shutdown provider (unloads local-llama model if active)
          await providerRegistry.shutdown();
        } catch {
          // Ignore shutdown errors on exit
        }
        exit();
        // Force process exit after a short delay to ensure cleanup
        setTimeout(() => process.exit(0), 100);
      })();
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

