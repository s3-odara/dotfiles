import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";
import process from "node:process";
import { spawnSync } from "node:child_process";

const root = new URL("..", import.meta.url).pathname;
const extensionPath = join(root, "extensions", "index.ts");
const source = await readFile(extensionPath, "utf8");
const typescriptSources = [
  extensionPath,
  join(root, "extension-src", "types.ts"),
  join(root, "extension-src", "osc99-notify", "index.ts"),
  join(root, "extension-src", "webfetch", "index.ts"),
  join(root, "extension-src", "skill-tmux-runner.ts"),
];

function fail(message: string) {
  console.error(`typescript compatibility check failed: ${message}`);
  process.exitCode = 1;
}

if (!/import\s+type\s+\{\s*ExtensionAPI\s*\}\s+from\s+["']\.\.\/extension-src\/types\.ts["'];/.test(source)) {
  fail("extension entry must use the local ExtensionAPI interface, not an unpinned external package");
}

if (!/export\s+default\s+function\s+piCodingKit\s*\(\s*pi\s*:\s*ExtensionAPI\s*\)\s*:\s*void\s*\{/.test(source)) {
  fail("extension entry must keep the documented default Pi factory signature");
}

if (!source.includes('from "../extension-src/osc99-notify/index.ts"') || !source.includes('from "../extension-src/webfetch/index.ts"') || !source.includes('from "../extension-src/skill-tmux-runner.ts"')) {
  fail("extension entry must import TypeScript implementation modules directly");
}

async function rejectJavaScriptFiles(directory: string) {
  const entries = await readdir(directory, { withFileTypes: true });
  for (const entry of entries) {
    if ([".git", "node_modules"].includes(entry.name)) continue;
    const entryPath = join(directory, entry.name);
    if (entry.isDirectory()) {
      await rejectJavaScriptFiles(entryPath);
    } else if (entry.name.endsWith(".mjs") || entry.name.endsWith(".js") || entry.name.endsWith(".cjs")) {
      // This repository intentionally ships TypeScript sources/scripts/tests only.
      // Keep the check repository-scoped so temporary test fixtures outside the repo
      // can still model Node executables without becoming package policy inputs.
      fail(`repository files must be TypeScript-only: ${entryPath}`);
    }
  }
}

await rejectJavaScriptFiles(root);

for (const sourcePath of typescriptSources) {
  const result = spawnSync(process.execPath, ["--check", sourcePath], { encoding: "utf8" });
  if (result.status !== 0) {
    fail(`Node TypeScript syntax check failed for ${sourcePath}: ${(result.stderr || result.stdout).trim()}`);
  }
}

if (!process.exitCode) console.log("typescript compatibility check passed");
