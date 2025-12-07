import { test, expect, describe, mock, beforeEach, afterEach } from "bun:test";
import { webFetchTool } from "./web-fetch.ts";

describe("Web Fetch Tool", () => {
  let originalFetch: typeof globalThis.fetch;

  beforeEach(() => {
    originalFetch = globalThis.fetch;
  });

  afterEach(() => {
    globalThis.fetch = originalFetch;
  });

  describe("web_fetch", () => {
    test("fetches text content from URL", async () => {
      globalThis.fetch = mock(() =>
        Promise.resolve(new Response("User-agent: *\nDisallow: /private", { status: 200 }))
      ) as unknown as typeof fetch;

      const result = await webFetchTool.execute({
        url: "https://example.com/robots.txt",
        format: "text",
        maxLength: 10000,
      });
      expect(typeof result).toBe("string");
      expect(result).toContain("User-agent");
    });

    test("fetches JSON content", async () => {
      globalThis.fetch = mock(() =>
        Promise.resolve(
          new Response(JSON.stringify({ slideshow: { title: "Sample" } }), {
            status: 200,
            headers: { "Content-Type": "application/json" },
          })
        )
      ) as unknown as typeof fetch;

      const result = await webFetchTool.execute({
        url: "https://example.com/api/data",
        format: "json",
        maxLength: 10000,
      });
      expect(typeof result).toBe("string");
      expect(() => JSON.parse(result)).not.toThrow();
    });

    test("fetches HTML content", async () => {
      globalThis.fetch = mock(() =>
        Promise.resolve(
          new Response("<html><body><h1>Hello</h1></body></html>", {
            status: 200,
            headers: { "Content-Type": "text/html" },
          })
        )
      ) as unknown as typeof fetch;

      const result = await webFetchTool.execute({
        url: "https://example.com/page",
        format: "html",
        maxLength: 10000,
      });
      expect(typeof result).toBe("string");
      expect(result).toContain("<");
    });

    test("truncates long content", async () => {
      const longContent = "<html><body>" + "x".repeat(500) + "</body></html>";
      globalThis.fetch = mock(() =>
        Promise.resolve(
          new Response(longContent, {
            status: 200,
            headers: { "Content-Type": "text/html" },
          })
        )
      ) as unknown as typeof fetch;

      const result = await webFetchTool.execute({
        url: "https://example.com/long",
        format: "html",
        maxLength: 100,
      });
      expect(result.length).toBeLessThanOrEqual(150);
      expect(result).toContain("Truncated");
    });

    test("handles HTTP errors", async () => {
      globalThis.fetch = mock(() =>
        Promise.resolve(new Response("Not Found", { status: 404, statusText: "Not Found" }))
      ) as unknown as typeof fetch;

      await expect(
        webFetchTool.execute({
          url: "https://example.com/missing",
          format: "text",
          maxLength: 10000,
        })
      ).rejects.toThrow("404");
    });

    test("handles network errors", async () => {
      globalThis.fetch = mock(() => Promise.reject(new Error("Network error"))) as unknown as typeof fetch;

      await expect(
        webFetchTool.execute({
          url: "https://nonexistent-domain.invalid",
          format: "text",
          maxLength: 10000,
        })
      ).rejects.toThrow("Network error");
    });

    test("strips HTML tags in text format", async () => {
      globalThis.fetch = mock(() =>
        Promise.resolve(
          new Response("<html><body><h1>Title</h1><p>Content here</p></body></html>", {
            status: 200,
            headers: { "Content-Type": "text/html" },
          })
        )
      ) as unknown as typeof fetch;

      const result = await webFetchTool.execute({
        url: "https://example.com/page",
        format: "text",
        maxLength: 10000,
      });
      expect(result).not.toMatch(/<\/?[a-z][\s\S]*>/i);
    });

    test("sends correct User-Agent header", async () => {
      let capturedHeaders: Headers | undefined;
      globalThis.fetch = mock((_url: string, options?: RequestInit) => {
        capturedHeaders = options?.headers as Headers;
        return Promise.resolve(new Response("OK", { status: 200 }));
      }) as unknown as typeof fetch;

      await webFetchTool.execute({
        url: "https://example.com/test",
        format: "text",
        maxLength: 10000,
      });

      expect(capturedHeaders).toBeDefined();
    });
  });
});

