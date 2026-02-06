import { z } from "zod";
import { defineTool } from "./base.ts";

/**
 * Check if a hostname resolves to a private/internal IP address
 * This prevents SSRF attacks where the agent is tricked into fetching internal resources
 */
function isPrivateOrReservedHost(hostname: string): boolean {
  // Block obvious localhost variations
  const localhostPatterns = ["localhost", "127.0.0.1", "::1", "0.0.0.0"];
  if (localhostPatterns.includes(hostname.toLowerCase())) {
    return true;
  }

  // Block IP addresses in private ranges
  // This is a basic check - for production, you'd want to resolve DNS and check the IP
  const ipv4Match = hostname.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/);
  if (ipv4Match) {
    const [, a, b] = ipv4Match.map(Number);
    // 10.0.0.0/8 - Private
    if (a === 10) return true;
    // 172.16.0.0/12 - Private
    if (a === 172 && b !== undefined && b >= 16 && b <= 31) return true;
    // 192.168.0.0/16 - Private
    if (a === 192 && b === 168) return true;
    // 169.254.0.0/16 - Link-local
    if (a === 169 && b === 254) return true;
    // 127.0.0.0/8 - Loopback
    if (a === 127) return true;
    // 0.0.0.0/8 - Current network
    if (a === 0) return true;
  }

  // Block common internal hostnames
  const internalPatterns = [
    /^192\.168\./,
    /^10\./,
    /^172\.(1[6-9]|2[0-9]|3[0-1])\./,
    /\.local$/i,
    /\.internal$/i,
    /\.corp$/i,
    /\.lan$/i,
  ];
  for (const pattern of internalPatterns) {
    if (pattern.test(hostname)) return true;
  }

  return false;
}

export const webFetchTool = defineTool({
  name: "web_fetch",
  description: "Fetch content from a URL and return it as text. Useful for reading web pages, APIs, or documentation.",
  category: "utility",
  requiresConfirmation: true,
  parameters: z.object({
    url: z.string().url().describe("The URL to fetch"),
    format: z
      .enum(["text", "json", "html"])
      .optional()
      .default("text")
      .describe("Response format: text (default), json, or html"),
    maxLength: z
      .number()
      .optional()
      .default(10000)
      .describe("Maximum response length in characters"),
  }),
  execute: async ({ url, format, maxLength }) => {
    try {
      // SSRF protection: block requests to private/internal networks
      const parsedUrl = new URL(url);
      if (isPrivateOrReservedHost(parsedUrl.hostname)) {
        throw new Error("Blocked: Cannot fetch from private or internal network addresses");
      }

      const response = await fetch(url, {
        headers: {
          "User-Agent": "Clarissa/1.0 (AI Assistant)",
          Accept: format === "json" ? "application/json" : "text/html,text/plain,*/*",
        },
      });

      if (!response.ok) {
        throw new Error(`HTTP ${response.status} ${response.statusText}`);
      }

      let content: string;

      if (format === "json") {
        const json = await response.json();
        content = JSON.stringify(json, null, 2);
      } else {
        content = await response.text();

        // Strip HTML tags for text format
        if (format === "text" && content.includes("<")) {
          content = content
            .replace(/<script[^>]*>[\s\S]*?<\/script>/gi, "")
            .replace(/<style[^>]*>[\s\S]*?<\/style>/gi, "")
            .replace(/<[^>]+>/g, " ")
            .replace(/\s+/g, " ")
            .trim();
        }
      }

      // Truncate if too long
      if (content.length > maxLength) {
        content = content.slice(0, maxLength) + `\n\n[Truncated - ${content.length} total characters]`;
      }

      return content;
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      throw new Error(`Failed to fetch URL: ${msg}`);
    }
  },
});

