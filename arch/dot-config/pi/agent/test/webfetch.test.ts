import assert from "node:assert/strict";
import { mkdtemp, readFile, readdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createServer, type ServerResponse } from "node:http";
import type { AddressInfo } from "node:net";
import { fetchUrl, registerWebfetchTool, validateHttpUrl } from "../extension-src/webfetch/index.ts";

await assert.rejects(async () => validateHttpUrl("file:///etc/passwd"), /only http and https/);
await assert.rejects(async () => validateHttpUrl("not a url"), /invalid URL/);

function delayed(response: ServerResponse, ms: number, reply: () => void) {
  const timer = setTimeout(reply, ms);
  response.once("close", () => clearTimeout(timer));
}

const server = createServer((request, response) => {
  switch (request.url) {
    case "/ok":
      response.writeHead(200, { "content-type": "text/plain" });
      response.end("ok");
      break;
    case "/large":
      response.writeHead(200, { "content-type": "text/plain" });
      response.end("x".repeat(256));
      break;
    case "/slow":
      // Delay longer than the test timeout; the fetch implementation should
      // fail by timer rather than waiting for the server to finish.
      delayed(response, 2_000, () => {
        response.writeHead(200, { "content-type": "text/plain" });
        response.end("slow");
      });
      break;
    case "/slow-redirect":
      delayed(response, 650, () => {
        response.writeHead(302, { location: "/delayed-ok" });
        response.end();
      });
      break;
    case "/delayed-ok":
      delayed(response, 650, () => response.end("ok"));
      break;
    case "/empty":
      response.writeHead(204);
      response.end();
      break;
    case "/error":
      response.writeHead(500);
      response.end("internal error");
      break;
    case "/unresolved-redirect":
      response.writeHead(302);
      response.end();
      break;
    case "/not-modified":
      response.writeHead(304, { location: "/ok" });
      response.end();
      break;
    case "/redirect-missing":
      response.writeHead(302, { location: "/missing" });
      response.end();
      break;
    case "/redirect-ok":
      response.writeHead(302, { location: "/ok" });
      response.end();
      break;
    case "/redirect-loop":
      response.writeHead(302, { location: "/redirect-loop" });
      response.end();
      break;
    case "/redirect-file":
      response.writeHead(302, { location: "file:///etc/passwd" });
      response.end();
      break;
    default:
      response.writeHead(404, { "content-type": "text/plain" });
      response.end("missing");
  }
});

await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
const address = server.address() as AddressInfo;
const baseUrl = `http://127.0.0.1:${address.port}`;

const tempRoot = await mkdtemp(join(tmpdir(), "webfetch-test-"));

try {
  const result = await fetchUrl(`${baseUrl}/ok`, { timeoutMs: 1000, maxBytes: 64, redirectLimit: 0 }, undefined, tempRoot);
  assert.match(result.path, /^\.agents\/downloads\/\d+-[0-9a-f-]+$/);
  assert.equal(result.bytes, 2);
  assert.equal(result.status, 200);
  assert.equal(result.finalUrl, `${baseUrl}/ok`);
  assert.equal(await readFile(join(tempRoot, result.path), "utf8"), "ok");

  const redirected = await fetchUrl(`${baseUrl}/redirect-ok`, { timeoutMs: 1000, maxBytes: 64, redirectLimit: 1 }, undefined, tempRoot);
  assert.equal(redirected.bytes, 2);
  assert.equal(redirected.status, 200);
  assert.equal(redirected.finalUrl, `${baseUrl}/ok`);
  assert.equal(await readFile(join(tempRoot, redirected.path), "utf8"), "ok");

  const empty = await fetchUrl(`${baseUrl}/empty`, {}, undefined, tempRoot);
  assert.equal(empty.status, 204);
  assert.equal(empty.bytes, 0);
  assert.equal(await readFile(join(tempRoot, empty.path), "utf8"), "");

  const downloads = join(tempRoot, ".agents/downloads");
  const beforeFailures = (await readdir(downloads)).sort();
  for (const [path, status, finalPath] of [
    ["/missing", 404, "/missing"], ["/error", 500, "/error"],
    ["/unresolved-redirect", 302, "/unresolved-redirect"],
    ["/not-modified", 304, "/not-modified"], ["/redirect-missing", 404, "/missing"],
  ] as const) {
    await assert.rejects(() => fetchUrl(`${baseUrl}${path}`, {}, undefined, tempRoot),
      { message: `HTTP ${status} for ${baseUrl}${finalPath}` });
  }

  await assert.rejects(() => fetchUrl(`${baseUrl}/redirect-loop`, { timeoutMs: 1000, maxBytes: 64, redirectLimit: 0 }, undefined, tempRoot), /redirect limit exceeded/);
  await assert.rejects(() => fetchUrl(`${baseUrl}/redirect-file`, { timeoutMs: 1000, maxBytes: 64, redirectLimit: 1 }, undefined, tempRoot), /only http and https/);
  await assert.rejects(() => fetchUrl(`${baseUrl}/large`, { timeoutMs: 1000, maxBytes: 64, redirectLimit: 0 }, undefined, tempRoot), /byte limit exceeded/);
  await assert.rejects(() => fetchUrl(`${baseUrl}/slow`, { timeoutMs: 1000, maxBytes: 64, redirectLimit: 0 }, undefined, tempRoot), /timeout exceeded/);
  // Each hop takes less than 1s, but the chain exceeds the shared 1s budget.
  await assert.rejects(() => fetchUrl(`${baseUrl}/slow-redirect`, { timeoutMs: 1000 }, undefined, tempRoot), /timeout exceeded/);

  const cancelled = new AbortController();
  cancelled.abort();
  await assert.rejects(() => fetchUrl(`${baseUrl}/ok`, {}, cancelled.signal, tempRoot), /request aborted/);
  const inFlight = new AbortController();
  const abortTimer = setTimeout(() => inFlight.abort(), 50);
  try {
    await assert.rejects(() => fetchUrl(`${baseUrl}/slow`, {}, inFlight.signal, tempRoot), /request aborted/);
  } finally { clearTimeout(abortTimer); }
  assert.deepEqual((await readdir(downloads)).sort(), beforeFailures, "failures must not save success artifacts");

  let registeredTool: { execute(callId: string, input: { url: string; timeoutMs: number; maxBytes: number; redirectLimit: number }, signal?: AbortSignal, onUpdate?: unknown, ctx?: { cwd?: string }): Promise<unknown> } | undefined;
  registerWebfetchTool({ registerTool(tool) { registeredTool = tool as NonNullable<typeof registeredTool>; } });
  assert(registeredTool);
  const toolResult = await registeredTool.execute("call-1", { url: `${baseUrl}/ok`, timeoutMs: 1000, maxBytes: 64, redirectLimit: 0 }, undefined, undefined, { cwd: tempRoot }) as { content: Array<{ type: string; text: string }>; details: { path: string; bytes: number; status: number; finalUrl: string } };
  assert.match(toolResult.details.path, /^\.agents\/downloads\/\d+-[0-9a-f-]+$/);
  assert.equal(toolResult.details.bytes, 2);
  assert.equal(toolResult.details.status, 200);
  assert.equal(toolResult.details.finalUrl, `${baseUrl}/ok`);
  assert.deepEqual(toolResult.content, [{ type: "text", text: `${toolResult.details.path}\n2 bytes\nHTTP 200\nURL: ${baseUrl}/ok` }]);
  assert.equal(await readFile(join(tempRoot, toolResult.details.path), "utf8"), "ok");
  // Throwing marks a Pi tool call as failed; an isError property alone does not.
  await assert.rejects(() => registeredTool!.execute("call-error", { url: `${baseUrl}/error`, timeoutMs: 1000, maxBytes: 64, redirectLimit: 0 }, undefined, undefined, { cwd: tempRoot }), /HTTP 500/);
} finally {
  await new Promise<void>((resolve) => server.close(() => resolve()));
  await rm(tempRoot, { recursive: true, force: true });
}

if (process.env.PI_CODING_KIT_TEST_NETWORK === "1") {
  const tempNetworkRoot = await mkdtemp(join(tmpdir(), "webfetch-network-test-"));
  try {
    const result = await fetchUrl("https://example.com/", { timeoutMs: 15_000, maxBytes: 200_000, redirectLimit: 1 }, undefined, tempNetworkRoot);
    assert.match(await readFile(join(tempNetworkRoot, result.path), "utf8"), /Example Domain/i);
  } finally {
    await rm(tempNetworkRoot, { recursive: true, force: true });
  }
}

console.log("webfetch tests passed");
