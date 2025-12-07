#!/usr/bin/env bun
import { render } from "ink";
import { AppWithErrorBoundary } from "./ui/App.tsx";
import { Agent } from "./agent.ts";
import { agentConfig, AVAILABLE_MODELS } from "./config/index.ts";
import packageJson from "../package.json";

const VERSION = packageJson.version;
const NAME = packageJson.name;

function printVersion() {
  console.log(`${NAME} v${VERSION}`);
}

function printHelp() {
  console.log(`${NAME} v${VERSION} - AI-powered terminal assistant

Usage:
  ${NAME}                      Start interactive mode
  ${NAME} "<message>"          Send a message and get a response
  ${NAME} [options]

Options:
  -h, --help                 Show this help message
  -v, --version              Show version number
  -m, --model <model>        Use a specific model for this request
  --list-models              List available models
  --debug                    Enable debug output

Examples:
  ${NAME}                      Start interactive session
  ${NAME} "What is 2+2?"       Ask a quick question
  ${NAME} -m gpt-4o "Hello"    Use a specific model
  echo "Hello" | ${NAME}       Pipe input to ${NAME}

Interactive Commands:
  /help       Show available commands
  /model      Show or switch the current model
  /tools      List available tools
  /exit       Exit ${NAME}
`);
}

function listModels() {
  console.log("Available models:\n");
  for (const model of AVAILABLE_MODELS) {
    const current = model === agentConfig.model ? " (current)" : "";
    // Extract short name from model identifier (e.g., "anthropic/claude-sonnet-4" -> "claude-sonnet-4")
    const shortName = model.split("/").pop() || model;
    console.log(`  ${shortName.padEnd(28)} ${current}`);
  }
  console.log(`\nUse: ${NAME} -m <model> "<message>"`);
}

async function runOneShot(message: string, model?: string) {
  const debug = process.env.DEBUG === "true" || process.env.DEBUG === "1";

  if (model) {
    // Check if model is in available models list, or use as-is for custom models
    const resolvedModel = (AVAILABLE_MODELS as readonly string[]).includes(model) ? model : model;
    agentConfig.setModel(resolvedModel);
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
  } catch (error) {
    const msg = error instanceof Error ? error.message : "Unknown error";
    console.error(`Error: ${msg}`);
    process.exit(1);
  }
}

async function main() {
  const args = process.argv.slice(2);

  // Parse flags
  let model: string | undefined;
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
      listModels();
      process.exit(0);
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

  if (message) {
    // One-shot mode
    await runOneShot(message, model);
  } else {
    // Interactive mode
    console.clear();
    render(<AppWithErrorBoundary />);
  }
}

main();

