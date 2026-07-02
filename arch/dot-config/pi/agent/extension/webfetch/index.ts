import http from "node:http";
import https from "node:https";
import type { IncomingMessage } from "node:http";
import type { ExtensionAPI } from "../types.ts";

interface FetchOptions {
  timeoutMs?: number;
  maxBytes?: number;
  redirectLimit?: number;
}

interface FetchResult {
  text: string;
  status: number;
  url: string;
  bytes: number;
}

interface WebfetchParams {
  url: string;
  timeoutMs?: number;
  maxBytes?: number;
  redirectLimit?: number;
}

const DEFAULT_TIMEOUT_MS = 15_000;
const DEFAULT_MAX_BYTES = 1_000_000;
const DEFAULT_REDIRECT_LIMIT = 3;

export const webfetchParameters = {
  type: "object",
  additionalProperties: false,
  properties: {
    url: { type: "string", description: "HTTP or HTTPS URL to fetch" },
    timeoutMs: { type: "number", minimum: 1000, maximum: 120000, description: "Total request timeout in milliseconds" },
    maxBytes: { type: "number", minimum: 1, maximum: 5000000, description: "Maximum response body bytes" },
    redirectLimit: { type: "number", minimum: 0, maximum: 10, description: "Maximum manual redirects" },
  },
  required: ["url"],
};

export function validateHttpUrl(rawUrl: string): URL {
  let url: URL;
  try {
    url = new URL(rawUrl);
  } catch {
    throw new Error("invalid URL");
  }

  if (!isHttpProtocol(url)) throw new Error("only http and https URLs are supported");
  if (!url.hostname) throw new Error("URL must include a host");
  return url;
}

function isHttpProtocol(url: URL): boolean {
  return url.protocol === "http:" || url.protocol === "https:";
}

function clampedNumber(value: number | undefined, fallback: number, minimum: number, maximum: number): number {
  return Math.min(Math.max(Number(value ?? fallback), minimum), maximum);
}

async function requestUrl(url: URL, timeoutMs: number, maxBytes: number, signal?: AbortSignal): Promise<{ text: string; status: number; location?: string; bytes: number }> {
  const client = url.protocol === "https:" ? https : http;

  return await new Promise((resolve, reject) => {
    let settled = false;
    let timedOut = false;
    let byteLimitExceeded = false;
    const chunks: Buffer[] = [];
    let total = 0;

    const fail = (error: Error) => {
      if (settled) return;
      settled = true;
      cleanup();
      reject(error);
    };
    const cleanup = () => {
      clearTimeout(timer);
      signal?.removeEventListener("abort", onAbort);
    };
    const onAbort = () => {
      // Surface the tool cancellation as a thrown failure, matching the rest of
      // the execute path instead of returning partial content.
      fail(new Error("request aborted"));
      request.destroy();
    };
    const timer = setTimeout(() => {
      timedOut = true;
      fail(new Error("timeout exceeded"));
      request.destroy();
    }, timeoutMs);

    const request = client.request(url, { method: "GET", headers: { accept: "text/*,*/*" } }, (response: IncomingMessage) => {
      response.on("data", (chunk: Buffer) => {
        total += chunk.length;
        if (total > maxBytes) {
          byteLimitExceeded = true;
          fail(new Error("byte limit exceeded"));
          response.destroy();
          request.destroy();
          return;
        }
        chunks.push(chunk);
      });
      response.on("end", () => {
        if (settled) return;
        settled = true;
        cleanup();
        resolve({
          text: Buffer.concat(chunks).toString("utf8"),
          status: response.statusCode ?? 0,
          location: response.headers.location,
          bytes: total,
        });
      });
      response.on("error", (error) => fail(error instanceof Error ? error : new Error(String(error))));
    });

    request.on("error", (error) => {
      if (timedOut) fail(new Error("timeout exceeded"));
      else if (byteLimitExceeded) fail(new Error("byte limit exceeded"));
      else fail(error instanceof Error ? error : new Error(String(error)));
    });

    signal?.addEventListener("abort", onAbort, { once: true });
    if (signal?.aborted) onAbort();
    request.end();
  });
}

export async function fetchUrl(rawUrl: string, options: FetchOptions = {}, signal?: AbortSignal): Promise<FetchResult> {
  const timeoutMs = clampedNumber(options.timeoutMs, DEFAULT_TIMEOUT_MS, 1000, 120_000);
  const maxBytes = clampedNumber(options.maxBytes, DEFAULT_MAX_BYTES, 1, 5_000_000);
  const redirectLimit = clampedNumber(options.redirectLimit, DEFAULT_REDIRECT_LIMIT, 0, 10);

  let url = validateHttpUrl(rawUrl);
  for (let redirects = 0; redirects <= redirectLimit; redirects += 1) {
    const result = await requestUrl(url, timeoutMs, maxBytes, signal);
    if (result.status >= 300 && result.status < 400 && result.location) {
      if (redirects === redirectLimit) throw new Error("redirect limit exceeded");
      // Re-parse and re-check every redirect target so an initially safe URL
      // cannot switch to file:, data:, or another non-HTTP(S) protocol.
      url = validateHttpUrl(new URL(result.location, url).toString());
      continue;
    }
    return { text: result.text, status: result.status, url: url.toString(), bytes: result.bytes };
  }
}

export function registerWebfetchTool(pi: ExtensionAPI): void {
  if (typeof pi?.registerTool !== "function") {
    console.warn("pi-coding-kit: webfetch disabled because pi.registerTool is unavailable");
    return;
  }
  pi.registerTool({
    name: "webfetch",
    label: "Web Fetch",
    description: "Fetch a specific HTTP/HTTPS URL as text with timeout, byte, and redirect protections.",
    promptSnippet: "Fetch a specific URL as text; this is not a web search tool.",
    promptGuidelines: ["Use webfetch only when the user provides a specific URL or asks to fetch a known page; do not use it for web search."],
    parameters: webfetchParameters,
    async execute(_toolCallId: string, params: WebfetchParams, signal?: AbortSignal) {
      const result = await fetchUrl(params.url, params, signal);
      return { content: [{ type: "text", text: result.text }], details: result };
    },
  });
}
