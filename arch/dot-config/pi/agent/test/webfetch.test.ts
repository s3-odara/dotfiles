import assert from "node:assert/strict";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";
import { fetchUrl, registerWebfetchTool, validateHttpUrl } from "../extension-src/webfetch/index.ts";

await assert.rejects(async () => validateHttpUrl("file:///etc/passwd"), /only http and https/);
await assert.rejects(async () => validateHttpUrl("not a url"), /invalid URL/);

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
      setTimeout(() => {
        response.writeHead(200, { "content-type": "text/plain" });
        response.end("slow");
      }, 2_000);
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
  assert.equal(await readFile(join(tempRoot, result.path), "utf8"), "ok");

  const redirected = await fetchUrl(`${baseUrl}/redirect-ok`, { timeoutMs: 1000, maxBytes: 64, redirectLimit: 1 }, undefined, tempRoot);
  assert.equal(redirected.bytes, 2);
  assert.equal(await readFile(join(tempRoot, redirected.path), "utf8"), "ok");

  await assert.rejects(() => fetchUrl(`${baseUrl}/redirect-loop`, { timeoutMs: 1000, maxBytes: 64, redirectLimit: 0 }, undefined, tempRoot), /redirect limit exceeded/);
  await assert.rejects(() => fetchUrl(`${baseUrl}/redirect-file`, { timeoutMs: 1000, maxBytes: 64, redirectLimit: 1 }, undefined, tempRoot), /only http and https/);
  await assert.rejects(() => fetchUrl(`${baseUrl}/large`, { timeoutMs: 1000, maxBytes: 64, redirectLimit: 0 }, undefined, tempRoot), /byte limit exceeded/);
  await assert.rejects(() => fetchUrl(`${baseUrl}/slow`, { timeoutMs: 1000, maxBytes: 64, redirectLimit: 0 }, undefined, tempRoot), /timeout exceeded/);

  let registeredTool: { execute(callId: string, input: { url: string; timeoutMs: number; maxBytes: number; redirectLimit: number }, signal?: AbortSignal, onUpdate?: unknown, ctx?: { cwd?: string }): Promise<unknown> } | undefined;
  registerWebfetchTool({ registerTool(tool) { registeredTool = tool; } });
  assert(registeredTool);
  const toolResult = await registeredTool.execute("call-1", { url: `${baseUrl}/ok`, timeoutMs: 1000, maxBytes: 64, redirectLimit: 0 }, undefined, undefined, { cwd: tempRoot }) as { content: Array<{ type: string; text: string }>; details: { path: string; bytes: number } };
  assert.match(toolResult.details.path, /^\.agents\/downloads\/\d+-[0-9a-f-]+$/);
  assert.equal(toolResult.details.bytes, 2);
  assert.deepEqual(toolResult.content, [{ type: "text", text: `${toolResult.details.path}\n2 bytes` }]);
  assert.equal(await readFile(join(tempRoot, toolResult.details.path), "utf8"), "ok");
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
