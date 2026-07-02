import { readdir, readFile } from "node:fs/promises";
import { join, relative } from "node:path";
import process from "node:process";

const root = new URL("..", import.meta.url).pathname;
// This agent directory is private dotfiles-owned material, not a publishable
// npm package. The README documents the dotfiles-native layout instead of a
// GitHub install pin, so the public-kit README assertions were dropped when
// pi-coding-kit was integrated here. The checks below still guard the parts
// that matter for a daily-driver agent: no runtime dependencies, no secret
// filenames, no forbidden runtime references in shipped source.
const forbiddenRuntimePackages = new Set(["pi-interactive-subagents", "pi-subagents"]);
const forbiddenFilenameFragments = [".env", "credential", "secret", "token"];
const allowedSensitiveFilenames = new Set([".env.example"]);
const textFilePattern = /(?:^|\/)(?:README|package|\.gitignore)$|\.(?:cjs|cts|js|json|md|mjs|mts|sh|ts|tsx|txt|yaml|yml)$/i;
const policyFiles = new Set(["scripts/check-policy.ts"]);
const forbiddenRuntimeReferences = [
  { name: "pi-interactive-subagents package", pattern: /\bpi-interactive-subagents\b/ },
  { name: "pi-subagents package", pattern: /\bpi-subagents\b/ },
  { name: "subagent API call", pattern: /\bsubagent\s*\(/ },
  { name: "bwrap runtime requirement", pattern: /\bbwrap\b/ },
  { name: "cmux multiplexer fallback", pattern: /\bcmux\b/ },
  { name: "zellij multiplexer fallback", pattern: /\bzellij\b/ },
  { name: "WezTerm multiplexer fallback", pattern: /\bWezTerm\b/i },
  { name: "custom websearch runtime", pattern: /\bwebsearch\b/i },
];
const allowedDocumentationLines = new Set([
  "- bwrap requirements",
  "- custom websearch tools",
]);

async function readJson(path: string) {
  return JSON.parse(await readFile(path, "utf8"));
}

async function walk(dir: string, files: string[] = []) {
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    if ([".git", "node_modules"].includes(entry.name)) continue;
    const path = join(dir, entry.name);
    if (entry.isDirectory()) await walk(path, files);
    else files.push(path);
  }
  return files;
}

function fail(message: string) {
  console.error(`policy check failed: ${message}`);
  process.exitCode = 1;
}

const packageJson = await readJson(join(root, "package.json"));
const dependencyBlocks = [
  packageJson.dependencies ?? {},
  packageJson.devDependencies ?? {},
  packageJson.optionalDependencies ?? {},
  packageJson.peerDependencies ?? {},
];

for (const deps of dependencyBlocks) {
  for (const name of Object.keys(deps)) {
    if (forbiddenRuntimePackages.has(name)) fail(`forbidden dependency ${name}`);
  }
}

for (const [scriptName, command] of Object.entries(packageJson.scripts ?? {})) {
  if (scriptName.includes("publish") || /npm\s+publish/.test(command)) {
    fail("npm publish automation is not allowed");
  }
}

const readme = await readFile(join(root, "README.md"), "utf8");
if (/git:github\.com\/.+@<commit-sha>/.test(readme)) {
  fail("README must not retain pi-coding-kit GitHub commit-SHA install language; the kit is integrated here");
}
if (/Publishing this package to npm is not intended/.test(readme)) {
  fail("README must not retain pi-coding-kit npm-publish language; the kit is integrated here");
}
if (/\bpi-coding-kit\b/.test(readme)) {
  fail("README must not reference pi-coding-kit as an external package; it is integrated here");
}

for (const file of await walk(root)) {
  const rel = relative(root, file);
  // Names like this are enough to indicate local secret material in this agent directory.
  // Template files such as .env.example are allowed because they document names,
  // not secret values, and are explicitly unignored for future config examples.
  if (!allowedSensitiveFilenames.has(rel) && forbiddenFilenameFragments.some((fragment) => rel.toLowerCase().includes(fragment))) {
    fail(`sensitive-looking file name is tracked: ${rel}`);
  }

  if (!textFilePattern.test(rel) || policyFiles.has(rel)) continue;

  const content = await readFile(file, "utf8");
  const lines = content.split(/\r?\n/);
  for (const [index, line] of lines.entries()) {
    for (const reference of forbiddenRuntimeReferences) {
      if (!reference.pattern.test(line)) continue;
      // Keep the Markdown allowance exact. Broad regex allowlists let a runtime
      // example hide on the same line as policy wording, which defeats the
      // guardrail this check is intended to provide.
      if (rel.endsWith(".md") && allowedDocumentationLines.has(line.trim())) continue;
      fail(`${rel}:${index + 1} contains forbidden runtime reference (${reference.name})`);
    }
  }
}

if (!process.exitCode) console.log("policy check passed");

