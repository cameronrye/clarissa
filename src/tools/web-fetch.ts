import { z } from "zod";
import { defineTool } from "./base.ts";

export const webFetchTool = defineTool({
  name: "web_fetch",
  description: "Fetch content from a URL and return it as text. Useful for reading web pages, APIs, or documentation.",
  category: "utility",
  requiresConfirmation: false,
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

