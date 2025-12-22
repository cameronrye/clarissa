#!/usr/bin/env bun
import { render } from "ink";
import { AppWithErrorBoundary, AppWithSession } from "./ui/App.tsx";
import { Agent } from "./agent.ts";
import { agentConfig, initConfig, CONFIG_FILE, CONFIG_DIR } from "./config/index.ts";
import { providerRegistry } from "./llm/providers/index.ts";
import { checkForUpdates, runUpgrade, runCheckUpdate, CURRENT_VERSION, PACKAGE_NAME } from "./update.ts";
import { sessionManager } from "./session/index.ts";
import { historyManager } from "./history/index.ts";
import {
  RECOMMENDED_MODELS,
  downloadModel,
  formatBytes,
  formatSpeed,
  getModelPath,
  isModelDownloaded,
  listDownloadedModels,
  MODELS_DIR,
} from "./models/download.ts";
import * as readline from "readline";
import { existsSync } from "fs";

const VERSION = CURRENT_VERSION;
const NAME = PACKAGE_NAME;

function printVersion() {
  console.log(`${NAME} v${VERSION}`);
}

function printHelp() {
  console.log(`${NAME} v${VERSION} - AI-powered terminal assistant

Usage:
  ${NAME}                      Start interactive mode
  ${NAME} "<message>"          Send a message and get a response
  ${NAME} [options]

Commands:
  init                       Set up Clarissa with your API key
  upgrade                    Upgrade to the latest version
  config                     View current configuration
  history                    Show one-shot query history
  providers [NAME]           List providers or switch to one
  download [MODEL_ID]        Download a local GGUF model
  models                     List downloaded models
  use <MODEL_FILE>           Set a downloaded model as active

Options:
  -h, --help                 Show this help message
  -v, --version              Show version number
  -c, --continue             Continue the last session
  -m, --model <model>        Use a specific model for this request
  --list-models              List available models
  --check-update             Check for available updates
  --debug                    Enable debug output

Examples:
  ${NAME} init                 Set up your API key
  ${NAME} upgrade              Upgrade to latest version
  ${NAME} providers            List available providers
  ${NAME} providers local-llama  Switch to local model
  ${NAME} download             Download a local model
  ${NAME} models               List downloaded models
  ${NAME} use Qwen2.5-7B.gguf  Set model as active
  ${NAME} -c                   Continue last session
  ${NAME}                      Start interactive session
  ${NAME} "What is 2+2?"       Ask a quick question
  ${NAME} -m gpt-4o "Hello"    Use a specific model
  echo "Hello" | ${NAME}       Pipe input to ${NAME}
  ${NAME} app "What's today?"  Ask via macOS app (Apple Intelligence)

Interactive Commands:
  /help       Show available commands
  /new        Start a new conversation
  /last       Load the most recent session
  /model      Show or switch the current model
  /provider   Show or switch the LLM provider
  /tools      List available tools
  /version    Show version info
  /upgrade    Upgrade to latest version
  /exit       Exit ${NAME}
`);
}

async function listModels() {
  // Initialize provider to get available models
  try {
    await providerRegistry.getActiveProvider();
  } catch {
    // Provider not available, will show message below
  }

  const availableModels = providerRegistry.getAvailableModels();
  const providerId = providerRegistry.getActiveProviderId();

  if (!availableModels || availableModels.length === 0) {
    console.log(`Current provider: ${providerId || "none"}\n`);
    console.log("This provider uses a fixed or dynamically loaded model.");
    console.log("Model selection is not available.\n");
    console.log(`Current model: ${agentConfig.model}`);
    return;
  }

  console.log(`Available models for ${providerId}:\n`);
  for (const model of availableModels) {
    const current = model === agentConfig.model ? " (current)" : "";
    // Extract short name from model identifier (e.g., "anthropic/claude-sonnet-4" -> "claude-sonnet-4")
    const shortName = model.split("/").pop() || model;
    console.log(`  ${shortName.padEnd(28)} ${current}`);
  }
  console.log(`\nUse: ${NAME} -m <model> "<message>"`);
}

async function runOneShot(message: string, model?: string) {
  const debug = process.env.DEBUG === "true" || process.env.DEBUG === "1";

  // Initialize context manager for active provider
  try {
    const { contextManager } = await import("./llm/context.ts");
    const { usageTracker } = await import("./llm/usage.ts");
    const provider = await providerRegistry.getActiveProvider();
    const providerModel = model || provider.info.availableModels?.[0] || provider.info.id;
    contextManager.setModel(providerModel);
    usageTracker.setModel(providerModel);
  } catch {
    // Provider initialization may fail, context will use defaults
  }

  if (model) {
    // Set the model directly - validation happens at provider level
    agentConfig.setModel(model);
  }

  const agent = new Agent({
    onToolCall: (name, _args) => {
      if (debug) {
        console.error(`[Tool: ${name}]`);
      }
    },
    onToolResult: (name, result) => {
      if (debug) {
        console.error(`[Result: ${name}] ${result.slice(0, 100)}...`);
      }
    },
    onError: (error) => {
      console.error(`Error: ${error.message}`);
    },
  });

  try {
    const response = await agent.run(message);
    console.log(response);

    // Save to history
    await historyManager.add(message, response, agentConfig.model);
  } catch (error) {
    const msg = error instanceof Error ? error.message : "Unknown error";
    console.error(`Error: ${msg}`);
    process.exit(1);
  }
}

function maskApiKey(key: string | undefined): string {
  if (!key) return "Not set";
  return "****" + key.slice(-4);
}

async function runConfig() {
  console.log(`Clarissa Configuration\n`);
  console.log(`Config file: ${CONFIG_FILE}`);
  console.log(`Config dir:  ${CONFIG_DIR}\n`);

  if (!existsSync(CONFIG_FILE)) {
    console.log("No config file found. Run 'clarissa init' to set up.");
    return;
  }

  try {
    const content = await Bun.file(CONFIG_FILE).json();
    console.log("API Keys:");
    console.log(`  OpenRouter: ${maskApiKey(content.openrouterApiKey)}`);
    console.log(`  OpenAI:     ${maskApiKey(content.openaiApiKey)}`);
    console.log(`  Anthropic:  ${maskApiKey(content.anthropicApiKey)}`);

    if (content.mcpServers && Object.keys(content.mcpServers).length > 0) {
      console.log(`\nMCP Servers:`);
      for (const [name, cfg] of Object.entries(content.mcpServers)) {
        const config = cfg as { command: string; args?: string[] };
        console.log(`  - ${name}: ${config.command} ${config.args?.join(" ") || ""}`);
      }
    }
  } catch (error) {
    console.error("Failed to read config file");
  }
}

async function runHistory() {
  const entries = await historyManager.getRecent(20);

  if (entries.length === 0) {
    console.log("No history yet. Run some one-shot queries first.");
    return;
  }

  console.log(`Recent Queries (${entries.length}):\n`);

  for (const entry of entries) {
    const date = new Date(entry.timestamp).toLocaleString();
    const query = entry.query.length > 60 ? entry.query.slice(0, 57) + "..." : entry.query;
    console.log(`  ${date}`);
    console.log(`  > ${query}`);
    console.log();
  }
}

async function runInit() {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  const prompt = (question: string): Promise<string> =>
    new Promise((resolve) => rl.question(question, resolve));

  console.log("Clarissa Setup\n");
  console.log("Enter API keys for the providers you want to use.");
  console.log("Press Enter to skip any provider.\n");

  console.log("OpenRouter: https://openrouter.ai/keys");
  const openrouterApiKey = (await prompt("  API Key: ")).trim() || undefined;

  console.log("\nOpenAI: https://platform.openai.com/api-keys");
  const openaiApiKey = (await prompt("  API Key: ")).trim() || undefined;

  console.log("\nAnthropic: https://console.anthropic.com/settings/keys");
  const anthropicApiKey = (await prompt("  API Key: ")).trim() || undefined;

  if (!openrouterApiKey && !openaiApiKey && !anthropicApiKey) {
    console.error("\nError: At least one API key is required");
    rl.close();
    process.exit(1);
  }

  await initConfig({ openrouterApiKey, openaiApiKey, anthropicApiKey });
  console.log(`\nConfig saved to ${CONFIG_FILE}`);
  console.log("Run 'clarissa' to start chatting!");

  rl.close();
}

async function runDownload(modelId?: string) {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  const prompt = (question: string): Promise<string> =>
    new Promise((resolve) => rl.question(question, resolve));

  console.log("Download Local Model\n");
  console.log(`Models will be saved to: ${MODELS_DIR}\n`);

  // List available models
  console.log("Available models:\n");
  RECOMMENDED_MODELS.forEach((m, i) => {
    const num = (i + 1).toString().padStart(2, " ");
    console.log(`  ${num}. ${m.name}`);
    console.log(`      ${m.description}`);
    console.log(`      Size: ${m.size} | ID: ${m.id}\n`);
  });

  let selectedModel = RECOMMENDED_MODELS.find((m) => m.id === modelId);

  if (!selectedModel) {
    const choice = await prompt("Enter model number or ID (or 'q' to quit): ");
    const trimmed = choice.trim();

    // Check for quit
    if (trimmed.toLowerCase() === "q" || trimmed.toLowerCase() === "quit") {
      console.log("Cancelled.");
      rl.close();
      return;
    }

    // Try as number first
    const num = parseInt(trimmed, 10);
    if (!isNaN(num) && num >= 1 && num <= RECOMMENDED_MODELS.length) {
      selectedModel = RECOMMENDED_MODELS[num - 1];
    } else {
      // Try as exact ID match only
      selectedModel = RECOMMENDED_MODELS.find((m) => m.id === trimmed);
    }
  }

  if (!selectedModel) {
    console.error(`\nError: Invalid model selection. Use a number (1-${RECOMMENDED_MODELS.length}) or exact model ID.`);
    rl.close();
    process.exit(1);
  }

  // Check if already downloaded
  const alreadyDownloaded = await isModelDownloaded(selectedModel.file);
  if (alreadyDownloaded) {
    const destPath = getModelPath(selectedModel.file);
    console.log(`\nModel already downloaded: ${destPath}`);
    console.log(`\nTo use this model, add to ~/.clarissa/config.json:`);
    console.log(`  { "provider": "local-llama", "localModelPath": "${destPath}" }`);
    rl.close();
    return;
  }

  console.log(`\nDownloading: ${selectedModel.name}`);
  console.log(`Size: ${selectedModel.size}`);
  console.log(`From: huggingface.co/${selectedModel.repo}\n`);

  const confirm = await prompt("Continue? [Y/n] ");
  if (confirm.toLowerCase() === "n") {
    console.log("Cancelled.");
    rl.close();
    return;
  }

  rl.close();

  // Download with progress
  let lastPercent = -1;
  const destPath = await downloadModel(selectedModel.repo, selectedModel.file, (progress) => {
    const percent = Math.floor(progress.percent);
    if (percent !== lastPercent) {
      lastPercent = percent;
      const bar = "=".repeat(Math.floor(percent / 2)).padEnd(50, " ");
      const downloaded = formatBytes(progress.downloaded);
      const total = progress.total > 0 ? formatBytes(progress.total) : "?";
      const speed = formatSpeed(progress.speed);
      process.stdout.write(`\r[${bar}] ${percent}% | ${downloaded}/${total} | ${speed}   `);
    }
  });

  console.log(`\n\nDownload complete: ${destPath}`);
  console.log(`\nTo use this model, add to ~/.clarissa/config.json:`);
  console.log(`  { "provider": "local-llama", "localModelPath": "${destPath}" }`);
}

async function runModels() {
  console.log("Downloaded Models\n");
  console.log(`Location: ${MODELS_DIR}\n`);

  const models = await listDownloadedModels();

  if (models.length === 0) {
    console.log("No models downloaded yet.");
    console.log(`\nRun 'clarissa download' to download a model.`);
    return;
  }

  for (const filename of models) {
    const path = getModelPath(filename);
    const file = Bun.file(path);
    const size = formatBytes(file.size);
    console.log(`  ${filename}`);
    console.log(`    Size: ${size}`);
    console.log(`    Path: ${path}\n`);
  }
}

async function runProviders(providerName?: string) {
  if (providerName) {
    // Switch to the specified provider
    try {
      await providerRegistry.setActiveProvider(providerName as import("./llm/providers/types.ts").ProviderId);
      const provider = await providerRegistry.getActiveProvider();
      console.log(`Switched to provider: ${provider.info.name}`);

      // Save preference
      const { preferencesManager } = await import("./preferences/index.ts");
      await preferencesManager.setLastProvider(providerName as import("./llm/providers/types.ts").ProviderId);
    } catch (error) {
      const msg = error instanceof Error ? error.message : "Failed to switch provider";
      console.error(`Error: ${msg}`);
      process.exit(1);
    }
    return;
  }

  // List all providers with their status
  console.log("LLM Providers\n");

  const registered = providerRegistry.getRegisteredProviders();

  // Check each provider individually with timeout to handle slow/broken providers
  const checkWithTimeout = async (id: string): Promise<import("./llm/providers/types.ts").ProviderStatus> => {
    const provider = providerRegistry.getProvider(id as import("./llm/providers/types.ts").ProviderId);
    if (!provider) return { available: false, reason: "Provider not found" };

    try {
      const timeout = new Promise<import("./llm/providers/types.ts").ProviderStatus>((_, reject) =>
        setTimeout(() => reject(new Error("Timeout")), 3000)
      );
      const check = provider.checkAvailability();
      return await Promise.race([check, timeout]);
    } catch (error) {
      const msg = error instanceof Error ? error.message : "Unknown error";
      return { available: false, reason: msg };
    }
  };

  const activeId = providerRegistry.getActiveProviderId();

  for (const { id, name, description } of registered) {
    const status = await checkWithTimeout(id);
    const available = status?.available ? "available" : "unavailable";
    const current = id === activeId ? " (current)" : "";
    const reason = !status?.available && status?.reason ? ` - ${status.reason}` : "";
    const model = status?.available && status?.model ? ` [${status.model}]` : "";

    console.log(`  ${id}${current}`);
    console.log(`    ${name} - ${description}`);
    console.log(`    Status: ${available}${model}${reason}\n`);
  }

  console.log(`Switch with: ${NAME} providers <provider_id>`);
}

async function runUseModel(modelFile: string) {
  // Find the model in downloaded models
  const models = await listDownloadedModels();
  const match = models.find((m) => m === modelFile || m.toLowerCase().includes(modelFile.toLowerCase()));

  if (!match) {
    console.error(`Error: Model not found: ${modelFile}`);
    console.log(`\nAvailable models:`);
    for (const m of models) {
      console.log(`  ${m}`);
    }
    if (models.length === 0) {
      console.log("  (none - run 'clarissa download' first)");
    }
    process.exit(1);
  }

  const modelPath = getModelPath(match);

  // Update config file
  try {
    let configContent: Record<string, unknown> = {};
    const configFile = Bun.file(CONFIG_FILE);
    if (await configFile.exists()) {
      configContent = await configFile.json();
    }

    configContent.provider = "local-llama";
    configContent.localModelPath = modelPath;

    await Bun.write(CONFIG_FILE, JSON.stringify(configContent, null, 2) + "\n");

    console.log(`Model set as active: ${match}`);
    console.log(`Provider set to: local-llama`);
    console.log(`\nConfig updated: ${CONFIG_FILE}`);
    console.log(`\nRun 'clarissa' to start using this model.`);
  } catch (error) {
    const msg = error instanceof Error ? error.message : "Failed to update config";
    console.error(`Error: ${msg}`);
    process.exit(1);
  }
}

/**
 * Open the native Clarissa macOS app with an optional question
 * Uses the clarissa:// URL scheme for integration
 */
async function openNativeApp(question?: string) {
  const platform = process.platform;

  if (platform !== "darwin") {
    console.error("Error: The 'app' command is only available on macOS.");
    console.log("\nThe native Clarissa app uses Apple Intelligence which requires macOS.");
    process.exit(1);
  }

  let url = "clarissa://";

  if (question && question.trim()) {
    // URL encode the question and use the ask endpoint
    const encodedQuestion = encodeURIComponent(question.trim());
    url = `clarissa://ask?q=${encodedQuestion}`;
    console.log(`Opening Clarissa app with question: "${question}"`);
  } else {
    // Just open the app
    url = "clarissa://new";
    console.log("Opening Clarissa app...");
  }

  try {
    // Use macOS 'open' command to open the URL scheme
    const proc = Bun.spawn(["open", url], {
      stdout: "inherit",
      stderr: "inherit",
    });
    await proc.exited;

    if (proc.exitCode !== 0) {
      console.error("\nFailed to open Clarissa app. Is it installed?");
      console.log("Install from: https://apps.apple.com/app/clarissa-ai");
      process.exit(1);
    }
  } catch (error) {
    console.error("Error opening Clarissa app:", error);
    process.exit(1);
  }
}

async function main() {
  const args = process.argv.slice(2);

  // Parse flags
  let model: string | undefined;
  let continueSession = false;
  const positional: string[] = [];

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (!arg) continue;

    if (arg === "-h" || arg === "--help") {
      printHelp();
      process.exit(0);
    }

    if (arg === "-v" || arg === "--version") {
      printVersion();
      process.exit(0);
    }

    if (arg === "--list-models") {
      await listModels();
      process.exit(0);
    }

    if (arg === "--check-update") {
      await runCheckUpdate();
      process.exit(0);
    }

    if (arg === "init") {
      await runInit();
      process.exit(0);
    }

    if (arg === "upgrade") {
      await runUpgrade();
      process.exit(0);
    }

    if (arg === "config") {
      await runConfig();
      process.exit(0);
    }

    if (arg === "history") {
      await runHistory();
      process.exit(0);
    }

    if (arg === "download") {
      // Check if next arg is a model ID (not starting with -)
      const nextArg = args[i + 1];
      const modelId = nextArg && !nextArg.startsWith("-") ? nextArg : undefined;
      await runDownload(modelId);
      process.exit(0);
    }

    if (arg === "models") {
      await runModels();
      process.exit(0);
    }

    if (arg === "providers") {
      // Check if next arg is a provider name (not starting with -)
      const nextArg = args[i + 1];
      const providerName = nextArg && !nextArg.startsWith("-") ? nextArg : undefined;
      await runProviders(providerName);
      process.exit(0);
    }

    if (arg === "use") {
      const nextArg = args[i + 1];
      if (!nextArg || nextArg.startsWith("-")) {
        console.error("Error: 'use' command requires a model filename");
        console.log(`\nUsage: ${NAME} use <model_file>`);
        console.log(`\nRun '${NAME} models' to see downloaded models.`);
        process.exit(1);
      }
      await runUseModel(nextArg);
      process.exit(0);
    }

    if (arg === "app") {
      // Open native macOS app with optional question
      const remainingArgs = args.slice(i + 1).filter((a) => !a.startsWith("-"));
      const question = remainingArgs.join(" ");
      await openNativeApp(question);
      process.exit(0);
    }

    if (arg === "-c" || arg === "--continue") {
      continueSession = true;
      continue;
    }

    if (arg === "--debug") {
      process.env.DEBUG = "true";
      continue;
    }

    if (arg === "-m" || arg === "--model") {
      model = args[++i];
      if (!model) {
        console.error("Error: --model requires a value");
        process.exit(1);
      }
      continue;
    }

    // Not a flag, treat as positional
    positional.push(arg);
  }

  // Check for piped input
  let pipedInput = "";
  if (!process.stdin.isTTY) {
    const chunks: Buffer[] = [];
    for await (const chunk of process.stdin) {
      chunks.push(chunk);
    }
    pipedInput = Buffer.concat(chunks).toString("utf-8").trim();
  }

  // Determine message from positional args or piped input
  const message = positional.length > 0 ? positional.join(" ") : pipedInput;

  // Check for updates (async, non-blocking)
  checkForUpdates();

  if (message) {
    // One-shot mode
    await runOneShot(message, model);
  } else {
    // Interactive mode
    console.clear();

    // Load last session if --continue flag is set
    if (continueSession) {
      const session = await sessionManager.getLatest();
      if (session) {
        render(<AppWithSession initialSession={session} />);
      } else {
        console.log("No previous session found. Starting fresh.\n");
        render(<AppWithErrorBoundary />);
      }
    } else {
      render(<AppWithErrorBoundary />);
    }
  }
}

main();

