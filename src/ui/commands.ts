/**
 * Slash Command Dispatcher
 *
 * Extracts all slash command handling from App.tsx into testable,
 * standalone command handlers. Each command receives a context object
 * with the dependencies it needs.
 */

import { Agent } from "../agent.ts";
import { agentConfig } from "../config/index.ts";
import { sessionManager } from "../session/index.ts";
import { memoryManager } from "../memory/index.ts";
import { usageTracker } from "../llm/client.ts";
import { mcpClient } from "../mcp/index.ts";
import { toolRegistry } from "../tools/index.ts";
import { contextManager } from "../llm/context.ts";
import { CURRENT_VERSION, fetchLatestVersion, isNewerVersion } from "../update.ts";
import { providerRegistry, type ProviderId } from "../llm/providers/index.ts";
import { preferencesManager } from "../preferences/index.ts";
import type { SelectOption } from "./components/InteractiveSelect.tsx";

/**
 * Context passed to every command handler
 */
export interface CommandContext {
  agent: Agent;
  addMessage: (role: string, content: string) => void;
  clearMessages: () => void;
  setDisplayMessages: (msgs: Array<{ role: string; content: string }>) => void;
  setState: (state: string) => void;
  exit: () => void;
  showSelection: (type: "provider" | "model" | "session", title: string, options: SelectOption[]) => void;
  setUpgradeInfo: (info: { current: string; latest: string }) => void;
}

/**
 * Result of a command execution
 */
type CommandResult = "handled" | "not_a_command";

/**
 * Save session and shutdown provider for clean exit
 */
export async function cleanupAndExit(agent: Agent, exit: () => void): Promise<void> {
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
  try {
    await providerRegistry.shutdown();
  } catch {
    // Ignore shutdown errors on exit
  }
  exit();
  setTimeout(() => process.exit(0), 100);
}

// --- Individual command handlers ---

function handleHelp(ctx: CommandContext): void {
  ctx.addMessage("system", `Commands:
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
  Tab               - Show command suggestions when typing /`);
}

function handleClear(ctx: CommandContext): void {
  ctx.clearMessages();
  ctx.agent.reset();
}

function handleNew(ctx: CommandContext): void {
  ctx.clearMessages();
  ctx.agent.reset();
  ctx.addMessage("system", "Started new conversation");
}

function handleVersion(ctx: CommandContext): void {
  ctx.addMessage("system", `Clarissa v${CURRENT_VERSION}`);
}

async function handleUpgrade(ctx: CommandContext): Promise<void> {
  if (process.env.NODE_ENV === "development" || process.argv.includes("--hot")) {
    ctx.addMessage("system", "Upgrade not available in development mode.\nRun 'clarissa upgrade' from the command line instead.");
    return;
  }
  ctx.addMessage("system", "Checking for updates...");
  const latest = await fetchLatestVersion();
  if (!latest) {
    ctx.addMessage("error", "Failed to check for updates. Please try again later.");
    return;
  }
  if (!isNewerVersion(CURRENT_VERSION, latest)) {
    ctx.addMessage("system", `Already on latest version (${CURRENT_VERSION})`);
    return;
  }
  ctx.addMessage("system", `Update available: ${CURRENT_VERSION} -> ${latest}`);
  ctx.setUpgradeInfo({ current: CURRENT_VERSION, latest });
  ctx.setState("upgradeConfirm");
}

function handleYolo(ctx: CommandContext): void {
  const enabled = agentConfig.toggleAutoApprove();
  ctx.addMessage("system", enabled
    ? "Auto-approve enabled. Tool executions will no longer require confirmation."
    : "Auto-approve disabled. Tool executions will require confirmation.");
}

async function handleSave(ctx: CommandContext): Promise<void> {
  try {
    const current = sessionManager.getCurrent();
    if (!current) {
      await sessionManager.create();
    }
    sessionManager.updateMessages(ctx.agent.getMessagesForSave());
    await sessionManager.save();
    ctx.addMessage("system", `Session saved: ${sessionManager.getCurrent()?.name}`);
  } catch (error) {
    ctx.addMessage("error", error instanceof Error ? error.message : "Save failed");
  }
}

async function handleSessions(ctx: CommandContext): Promise<void> {
  try {
    const sessions = await sessionManager.list();
    if (sessions.length === 0) {
      ctx.addMessage("system", "No saved sessions");
    } else {
      const options: SelectOption[] = sessions.map((s) => ({
        label: s.name,
        value: s.id,
        hint: new Date(s.updatedAt).toLocaleDateString(),
      }));
      ctx.showSelection("session", "Select session to load", options);
    }
  } catch (error) {
    ctx.addMessage("error", error instanceof Error ? error.message : "List failed");
  }
}

async function handleLoad(ctx: CommandContext, args: string): Promise<void> {
  const sessionId = args.trim();
  if (!sessionId) {
    ctx.addMessage("error", "Usage: /load <session_id>\nUse /sessions to list available sessions.");
    return;
  }
  try {
    const session = await sessionManager.load(sessionId);
    if (session) {
      ctx.agent.loadMessages(session.messages);
      const displayMessages = session.messages
        .filter((m) => m.role === "user" || m.role === "assistant")
        .map((m) => ({ role: m.role, content: m.content || "" }));
      ctx.setDisplayMessages([...displayMessages, { role: "system", content: `Loaded session: ${session.name}` }]);
    } else {
      ctx.addMessage("error", `Session not found: ${sessionId}`);
    }
  } catch (error) {
    ctx.addMessage("error", error instanceof Error ? error.message : "Load failed");
  }
}

async function handleLast(ctx: CommandContext): Promise<void> {
  try {
    const session = await sessionManager.getLatest();
    if (session) {
      ctx.agent.loadMessages(session.messages);
      const displayMessages = session.messages
        .filter((m) => m.role === "user" || m.role === "assistant")
        .map((m) => ({ role: m.role, content: m.content || "" }));
      ctx.setDisplayMessages([...displayMessages, { role: "system", content: `Loaded session: ${session.name}` }]);
    } else {
      ctx.addMessage("system", "No saved sessions found");
    }
  } catch (error) {
    ctx.addMessage("error", error instanceof Error ? error.message : "Load failed");
  }
}

async function handleDelete(ctx: CommandContext, args: string): Promise<void> {
  const sessionId = args.trim();
  if (!sessionId) {
    ctx.addMessage("error", "Usage: /delete <session_id>\nUse /sessions to list available sessions.");
    return;
  }
  try {
    const deleted = await sessionManager.delete(sessionId);
    if (deleted) {
      ctx.addMessage("system", `Deleted session: ${sessionId}`);
    } else {
      ctx.addMessage("error", `Session not found: ${sessionId}`);
    }
  } catch (error) {
    ctx.addMessage("error", error instanceof Error ? error.message : "Delete failed");
  }
}

async function handleRemember(ctx: CommandContext, args: string): Promise<void> {
  const fact = args.trim();
  if (!fact) {
    ctx.addMessage("error", "Usage: /remember <fact>");
    return;
  }
  try {
    const memory = await memoryManager.add(fact);
    if (memory) {
      ctx.addMessage("system", `Remembered: ${fact}`);
    } else {
      ctx.addMessage("system", `Already remembered: ${fact}`);
    }
  } catch (error) {
    ctx.addMessage("error", error instanceof Error ? error.message : "Failed to save memory");
  }
}

async function handleMemories(ctx: CommandContext): Promise<void> {
  try {
    const memories = await memoryManager.list();
    if (memories.length === 0) {
      ctx.addMessage("system", "No saved memories");
    } else {
      const list = memories.map((m, i) => `  ${i + 1}. ${m.content}`).join("\n");
      ctx.addMessage("system", `Memories (${memories.length}):\n${list}\n\nUse /forget <#> to remove a memory`);
    }
  } catch (error) {
    ctx.addMessage("error", error instanceof Error ? error.message : "Failed to list memories");
  }
}

async function handleForget(ctx: CommandContext, args: string): Promise<void> {
  const idOrIndex = args.trim();
  if (!idOrIndex) {
    ctx.addMessage("error", "Usage: /forget <# or ID>\nUse /memories to list saved memories.");
    return;
  }
  try {
    const forgotten = await memoryManager.forget(idOrIndex);
    if (forgotten) {
      ctx.addMessage("system", "Memory forgotten");
    } else {
      ctx.addMessage("error", `Memory not found: ${idOrIndex}`);
    }
  } catch (error) {
    ctx.addMessage("error", error instanceof Error ? error.message : "Failed to forget memory");
  }
}

async function handleModel(ctx: CommandContext, args: string): Promise<void> {
  const availableModels = providerRegistry.getAvailableModels();
  const providerId = providerRegistry.getActiveProviderId();

  if (!args.trim()) {
    // Show interactive model selector
    if (!availableModels || availableModels.length === 0) {
      ctx.addMessage("system",
        `Current model: ${agentConfig.model}\n\nThe ${providerId || "current"} provider uses a fixed or dynamically loaded model that cannot be changed via /model.`);
    } else {
      const options: SelectOption[] = availableModels.map((m) => ({
        label: m.split("/").pop() || m,
        value: m,
        hint: m === agentConfig.model ? "(current)" : undefined,
      }));
      ctx.showSelection("model",
        `Select model for ${providerId} (current: ${agentConfig.model.split("/").pop()})`,
        options);
    }
    return;
  }

  const newModel = args.trim();

  if (!availableModels || availableModels.length === 0) {
    ctx.addMessage("error",
      `The ${providerId || "current"} provider uses a fixed or dynamically loaded model. Model selection is not available.\n\nUse /provider to switch to a different provider if you need to select a model.`);
    return;
  }

  if (!availableModels.includes(newModel)) {
    ctx.addMessage("error",
      `Unknown model: ${newModel}\n\nAvailable models for ${providerId}:\n${availableModels.map((m) => `  - ${m}`).join("\n")}`);
    return;
  }

  agentConfig.setModel(newModel);
  contextManager.setModel(newModel);
  usageTracker.setModel(newModel);
  await preferencesManager.setLastModel(newModel);
  ctx.addMessage("system", `Model switched to: ${newModel}`);
}

async function handleProvider(ctx: CommandContext, args: string): Promise<void> {
  if (!args.trim()) {
    try {
      const statuses = await providerRegistry.getProviderStatuses();
      const registered = providerRegistry.getRegisteredProviders();
      const activeProvider = await providerRegistry.getActiveProvider().catch(() => null);
      const activeId = activeProvider?.info.id;

      const options: SelectOption[] = [];
      for (const { id, name } of registered) {
        const status = statuses.get(id);
        if (status?.available) {
          const hint = id === activeId ? "(current)" : status.model ? `(${status.model})` : "";
          options.push({ label: `${id}: ${name}`, value: id, hint });
        }
      }

      if (options.length === 0) {
        ctx.addMessage("error", "No providers available");
      } else {
        ctx.showSelection("provider", `Select provider (current: ${activeId || "none"})`, options);
      }
    } catch (error) {
      ctx.addMessage("error", error instanceof Error ? error.message : "Failed to get provider status");
    }
    return;
  }

  const newProvider = args.trim() as ProviderId;
  try {
    await providerRegistry.setActiveProvider(newProvider);
    const provider = providerRegistry.getProvider(newProvider);
    const providerModel = provider?.info.availableModels?.[0] ?? newProvider;
    contextManager.setModel(providerModel);
    usageTracker.setModel(providerModel);
    await preferencesManager.setLastProvider(newProvider);
    ctx.addMessage("system", `Provider switched to: ${provider?.info.name || newProvider}`);
  } catch (error) {
    ctx.addMessage("error", error instanceof Error ? error.message : "Failed to switch provider");
  }
}

async function handleMcp(ctx: CommandContext, args: string): Promise<void> {
  if (!args.trim()) {
    // Show MCP status
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

    ctx.addMessage("system", content);
    return;
  }

  // Connect to an MCP server
  ctx.setState("thinking");
  const parts = args.trim().split(/\s+/);

  try {
    if (parts[0]?.toLowerCase() === "sse" && parts[1]) {
      const url = parts[1];
      const serverName = new URL(url).hostname.replace(/\./g, "-");
      ctx.addMessage("system", `Connecting to SSE server: ${url}...`);

      const tools = await mcpClient.connectSse(serverName, url);
      for (const tool of tools) {
        toolRegistry.register(tool);
      }
      ctx.addMessage("system",
        `Connected to ${serverName} (SSE)\nRegistered ${tools.length} tool(s): ${tools.map(t => t.name).join(", ")}`);
    } else {
      const command = parts[0]!;
      const cmdArgs = parts.slice(1);
      const serverName = command.replace(/[^a-zA-Z0-9]/g, "-");
      ctx.addMessage("system", `Connecting to: ${command} ${cmdArgs.join(" ")}...`);

      const tools = await mcpClient.connect({ name: serverName, command, args: cmdArgs });
      for (const tool of tools) {
        toolRegistry.register(tool);
      }
      ctx.addMessage("system",
        `Connected to ${serverName}\nRegistered ${tools.length} tool(s): ${tools.map(t => t.name).join(", ")}`);
    }
  } catch (error) {
    ctx.addMessage("error", `MCP connection failed: ${error instanceof Error ? error.message : "Connection failed"}`);
  }

  ctx.setState("idle");
}

function handleTools(ctx: CommandContext): void {
  const tools = toolRegistry.getToolNames();
  const mcpTools = toolRegistry.getByCategory("mcp");
  ctx.addMessage("system",
    `Available tools (${tools.length}):\n${tools.map((t) => `  - ${t}${mcpTools.some((m) => m.name === t) ? " (MCP)" : ""}`).join("\n")}`);
}

function handleContext(ctx: CommandContext): void {
  const stats = contextManager.getDetailedStats(ctx.agent.getHistory());
  const barWidth = 40;
  const filledWidth = Math.round((stats.usagePercent / 100) * barWidth);
  const emptyWidth = barWidth - filledWidth;
  const bar = `[${"=".repeat(filledWidth)}${" ".repeat(emptyWidth)}]`;

  const formatTokens = (n: number) => n.toLocaleString().padStart(8);
  const formatPercent = (tokens: number, total: number) =>
    total > 0 ? `${Math.round((tokens / total) * 100)}%`.padStart(4) : "  0%";

  const { breakdown: b } = stats;
  ctx.addMessage("system", `Context Usage: ${stats.usagePercent}%
${bar} ${stats.totalTokens.toLocaleString()}/${stats.maxTokens.toLocaleString()} tokens

Model: ${stats.model}
Response Reserve: ${stats.responseReserve.toLocaleString()} tokens

Breakdown by type:
  System:    ${formatTokens(b.system.tokens)} tokens (${formatPercent(b.system.tokens, stats.totalTokens)}) - ${b.system.count} message(s)
  User:      ${formatTokens(b.user.tokens)} tokens (${formatPercent(b.user.tokens, stats.totalTokens)}) - ${b.user.count} message(s)
  Assistant: ${formatTokens(b.assistant.tokens)} tokens (${formatPercent(b.assistant.tokens, stats.totalTokens)}) - ${b.assistant.count} message(s)
  Tool:      ${formatTokens(b.tool.tokens)} tokens (${formatPercent(b.tool.tokens, stats.totalTokens)}) - ${b.tool.count} message(s)`);
}

/**
 * Dispatch a slash command. Returns "handled" if the input was a command,
 * or "not_a_command" if it should be sent to the agent.
 */
export async function dispatchCommand(value: string, ctx: CommandContext): Promise<CommandResult> {
  const lower = value.toLowerCase();
  const spaceIndex = value.indexOf(" ");
  const command = spaceIndex === -1 ? lower : lower.slice(0, spaceIndex);
  const args = spaceIndex === -1 ? "" : value.slice(spaceIndex + 1);

  switch (command) {
    case "/exit":
    case "/quit":
      await cleanupAndExit(ctx.agent, ctx.exit);
      return "handled";

    case "/clear":
      handleClear(ctx);
      return "handled";

    case "/help":
      handleHelp(ctx);
      return "handled";

    case "/version":
      handleVersion(ctx);
      return "handled";

    case "/upgrade":
      await handleUpgrade(ctx);
      return "handled";

    case "/new":
      handleNew(ctx);
      return "handled";

    case "/yolo":
      handleYolo(ctx);
      return "handled";

    case "/save":
      await handleSave(ctx);
      return "handled";

    case "/sessions":
      await handleSessions(ctx);
      return "handled";

    case "/load":
      await handleLoad(ctx, args);
      return "handled";

    case "/last":
      await handleLast(ctx);
      return "handled";

    case "/delete":
      await handleDelete(ctx, args);
      return "handled";

    case "/remember":
      await handleRemember(ctx, args);
      return "handled";

    case "/memories":
      await handleMemories(ctx);
      return "handled";

    case "/forget":
      await handleForget(ctx, args);
      return "handled";

    case "/model":
      await handleModel(ctx, args);
      return "handled";

    case "/provider":
      await handleProvider(ctx, args);
      return "handled";

    case "/mcp":
      await handleMcp(ctx, args);
      return "handled";

    case "/tools":
      handleTools(ctx);
      return "handled";

    case "/context":
      handleContext(ctx);
      return "handled";

    default:
      // Unknown slash command
      if (value.startsWith("/")) {
        ctx.addMessage("error", `Unknown command: ${command}\nType /help to see available commands.`);
        return "handled";
      }
      return "not_a_command";
  }
}
