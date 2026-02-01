import { join } from "path";
import { existsSync } from "fs";
import { CONFIG_DIR } from "./config/index.ts";
import packageJson from "../package.json";

const UPDATE_CHECK_FILE = join(CONFIG_DIR, "update-check.json");
const CHECK_INTERVAL_MS = 24 * 60 * 60 * 1000; // 24 hours
const PACKAGE_NAME = packageJson.name;
const CURRENT_VERSION = packageJson.version;

interface UpdateCheckData {
  lastCheck: number;
  latestVersion: string | null;
}

/**
 * Check if enough time has passed since the last update check
 */
async function shouldCheckForUpdates(): Promise<boolean> {
  try {
    if (!existsSync(UPDATE_CHECK_FILE)) return true;
    const data: UpdateCheckData = JSON.parse(
      await Bun.file(UPDATE_CHECK_FILE).text()
    );
    return Date.now() - data.lastCheck > CHECK_INTERVAL_MS;
  } catch {
    return true;
  }
}

/**
 * Save update check result to cache file
 */
async function saveUpdateCheck(latestVersion: string | null): Promise<void> {
  try {
    const data: UpdateCheckData = {
      lastCheck: Date.now(),
      latestVersion,
    };
    await Bun.write(UPDATE_CHECK_FILE, JSON.stringify(data, null, 2) + "\n");
  } catch {
    // Silently fail - caching is not critical
  }
}

/**
 * Get cached update check result
 */
async function getCachedUpdate(): Promise<string | null> {
  try {
    if (!existsSync(UPDATE_CHECK_FILE)) return null;
    const data: UpdateCheckData = JSON.parse(
      await Bun.file(UPDATE_CHECK_FILE).text()
    );
    return data.latestVersion;
  } catch {
    return null;
  }
}

/**
 * Fetch latest version from npm registry
 */
export async function fetchLatestVersion(): Promise<string | null> {
  try {
    const response = await fetch(
      `https://registry.npmjs.org/${PACKAGE_NAME}/latest`,
      { signal: AbortSignal.timeout(3000) }
    );
    if (!response.ok) return null;
    const data = (await response.json()) as { version?: string };
    return data.version || null;
  } catch {
    return null;
  }
}

/**
 * Compare semver versions - returns true if latest > current
 */
export function isNewerVersion(current: string, latest: string): boolean {
  const currentParts = current.split(".").map(Number);
  const latestParts = latest.split(".").map(Number);

  for (let i = 0; i < 3; i++) {
    const c = currentParts[i] || 0;
    const l = latestParts[i] || 0;
    if (l > c) return true;
    if (l < c) return false;
  }
  return false;
}

/**
 * Check for updates asynchronously and notify if available
 * This is non-blocking and will not delay startup
 */
export async function checkForUpdates(): Promise<void> {
  // Skip in test environment
  if (
    process.env.NODE_ENV === "test" ||
    process.env.NO_UPDATE_NOTIFIER === "1"
  ) {
    return;
  }

  // First, show notification from cached result (if any)
  const cachedVersion = await getCachedUpdate();
  if (cachedVersion && isNewerVersion(CURRENT_VERSION, cachedVersion)) {
    showUpdateNotification(cachedVersion);
  }

  // Check if we should fetch new update info
  if (!(await shouldCheckForUpdates())) {
    return;
  }

  // Fetch in background - don't await, let it run async
  fetchLatestVersion()
    .then(async (latestVersion) => {
      if (latestVersion) {
        await saveUpdateCheck(latestVersion);
      }
    })
    .catch(() => {
      // Silently ignore errors - update check is not critical
    });
}

/**
 * Show update notification to user
 */
function showUpdateNotification(latestVersion: string): void {
  console.log(
    `\n  Update available: ${CURRENT_VERSION} -> ${latestVersion}`
  );
  console.log(`  Run 'clarissa upgrade' to update\n`);
}

/**
 * Detect which package manager was used to install clarissa
 */
async function detectPackageManager(): Promise<"bun" | "pnpm" | "npm"> {
  // Check if running via bun
  if (typeof Bun !== "undefined") {
    // Check if pnpm is available and was likely used
    try {
      const proc = Bun.spawn(["pnpm", "--version"], {
        stdout: "pipe",
        stderr: "pipe",
      });
      await proc.exited;
      if (proc.exitCode === 0) {
        // Check if installed via pnpm by looking for pnpm in the path
        const execPath = process.argv[0] || "";
        if (execPath.includes("pnpm")) {
          return "pnpm";
        }
      }
    } catch {
      // pnpm not available
    }

    return "bun";
  }

  return "npm";
}

/**
 * Run the upgrade command
 */
export async function runUpgrade(): Promise<void> {
  console.log("Checking for updates...\n");

  const latestVersion = await fetchLatestVersion();

  if (!latestVersion) {
    console.error("Failed to check for updates. Please try again later.");
    process.exit(1);
  }

  if (!isNewerVersion(CURRENT_VERSION, latestVersion)) {
    console.log(`Already on latest version (${CURRENT_VERSION})`);
    return;
  }

  console.log(`Upgrading ${CURRENT_VERSION} -> ${latestVersion}...\n`);

  const pm = await detectPackageManager();
  const installCmd = {
    bun: ["bun", "install", "-g", `${PACKAGE_NAME}@latest`],
    pnpm: ["pnpm", "add", "-g", `${PACKAGE_NAME}@latest`],
    npm: ["npm", "install", "-g", `${PACKAGE_NAME}@latest`],
  }[pm];

  console.log(`Using ${pm}: ${installCmd.join(" ")}\n`);

  const proc = Bun.spawn(installCmd, {
    stdout: "inherit",
    stderr: "inherit",
  });

  const exitCode = await proc.exited;

  if (exitCode === 0) {
    console.log("\nUpgrade complete!");
  } else {
    console.error("\nUpgrade failed. You may need to run with sudo:");
    console.error(`  sudo ${installCmd.join(" ")}`);
    process.exit(1);
  }
}

/**
 * Run manual update check (for --check-update flag)
 */
export async function runCheckUpdate(): Promise<void> {
  console.log("Checking for updates...\n");

  const latestVersion = await fetchLatestVersion();

  if (!latestVersion) {
    console.error("Failed to check for updates. Please try again later.");
    process.exit(1);
  }

  if (isNewerVersion(CURRENT_VERSION, latestVersion)) {
    console.log(`Update available: ${CURRENT_VERSION} -> ${latestVersion}`);
    console.log(`Run 'clarissa upgrade' to update`);
  } else {
    console.log(`Already on latest version (${CURRENT_VERSION})`);
  }

  // Update cache
  await saveUpdateCheck(latestVersion);
}

export { CURRENT_VERSION, PACKAGE_NAME };

