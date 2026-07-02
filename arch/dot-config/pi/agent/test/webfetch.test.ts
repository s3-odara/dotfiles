import assert from "node:assert/strict";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";
import { fetchUrl, registerWebfetchTool, validateHttpUrl } from "../extension/webfetch/index.ts";

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

try {
  const result = await fetchUrl(`${baseUrl}/ok`, { timeoutMs: 1000, maxBytes: 64, redirectLimit: 0 });
  assert.equal(result.text, "ok");
  assert.equal(result.status, 200);
  assert.equal(result.bytes, 2);

  const redirected = await fetchUrl(`${baseUrl}/redirect-ok`, { timeoutMs: 1000, maxBytes: 64, redirectLimit: 1 });
  assert.equal(redirected.text, "ok");
  assert.equal(redirected.url, `${baseUrl}/ok`);

  await assert.rejects(() => fetchUrl(`${baseUrl}/redirect-loop`, { timeoutMs: 1000, maxBytes: 64, redirectLimit: 0 }), /redirect limit exceeded/);
  await assert.rejects(() => fetchUrl(`${baseUrl}/redirect-file`, { timeoutMs: 1000, maxBytes: 64, redirectLimit: 1 }), /only http and https/);
  await assert.rejects(() => fetchUrl(`${baseUrl}/large`, { timeoutMs: 1000, maxBytes: 64, redirectLimit: 0 }), /byte limit exceeded/);
  await assert.rejects(() => fetchUrl(`${baseUrl}/slow`, { timeoutMs: 1000, maxBytes: 64, redirectLimit: 0 }), /timeout exceeded/);

  let registeredTool: { execute(callId: string, input: { url: string; timeoutMs: number; maxBytes: number; redirectLimit: number }): Promise<unknown> } | undefined;
  registerWebfetchTool({ registerTool(tool) { registeredTool = tool; } });
  assert(registeredTool);
  const toolResult = await registeredTool.execute("call-1", { url: `${baseUrl}/ok`, timeoutMs: 1000, maxBytes: 64, redirectLimit: 0 });
  assert.deepEqual(toolResult, { content: [{ type: "text", text: "ok" }], details: { text: "ok", status: 200, url: `${baseUrl}/ok`, bytes: 2 } });
} finally {
  await new Promise<void>((resolve) => server.close(() => resolve()));
}

if (process.env.PI_CODING_KIT_TEST_NETWORK === "1") {
  const result = await fetchUrl("https://example.com/", { timeoutMs: 15_000, maxBytes: 200_000, redirectLimit: 1 });
  assert.match(result.text, /Example Domain/i);
}

console.log("webfetch tests passed");
