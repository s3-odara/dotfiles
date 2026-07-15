import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, readdir, rm, stat, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawn, spawnSync } from "node:child_process";

const root = new URL("..", import.meta.url).pathname;
const helper = join(root, "skills", "scripts", "start-bg-pane.sh");
const waitHelper = join(root, "skills", "scripts", "wait-for-children.sh");

type TmuxFixture = { dir: string; bin: string; cwd: string; prompt: string };

async function makeFixture(): Promise<TmuxFixture> {
  const dir = await mkdtemp(join(tmpdir(), "pi-coding-kit-tmux-"));
  const bin = join(dir, "bin");
  const cwd = join(dir, "work");
  await mkdir(bin);
  await mkdir(cwd);
  const prompt = join(dir, "prompt.md");
  await writeFile(prompt, "You are a test prompt.\n");
await writeFile(join(bin, "tmux"), `#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  display-message)
    printf '%s\\n' "${'${PI_FAKE_TMUX_SESSION:-parent}'}"
    ;;
  list-windows)
    if [[ "${'${PI_FAKE_TMUX_HAS_AGENT:-1}'}" == "1" ]]; then printf 'agent\\n'; fi
    ;;
  has-session)
    exit 0
    ;;
  new-session)
    printf 'new-session %s\\n' "$*" >>"${dir}/tmux.log"
    ;;
  split-window|new-window)
    if [[ "${'${PI_FAKE_TMUX_MODE:-success}'}" == "fail" ]]; then
      printf 'fake tmux pane failure\n' >&2
      exit 42
    fi
    printf '%s %s\\n' "$1" "$*" >>"${dir}/tmux.log"
    command="${'${@: -1}'}"
    TMUX_PANE='%7' bash "$command" || true
    printf 'parent:1.2 %%7\\n'
    ;;
  kill-pane)
    printf 'kill-pane %s\\n' "$*" >>"${dir}/tmux.log"
    ;;
  *)
    printf 'unsupported fake tmux invocation: %s\\n' "$*" >&2
    exit 9
    ;;
esac
`, { mode: 0o755 });
  await writeFile(join(bin, "pi"), `#!/usr/bin/env bash
set -euo pipefail
case "${'${PI_FAKE_MODE:-success}'}" in
  success)
    if printf '%s\n' "$*" | grep -E -- '(^| )(-p|--no-session)( |$)' >/dev/null; then
      printf 'obsolete non-interactive flags used: %s\n' "$*" >&2
      exit 19
    fi
    printf '# Artifact\\n\\n%s\\n' "$PI_CHILD_RUNNER_SKILL" >"$PI_CHILD_RUNNER_ARTIFACT_PATH"
    "$PI_CHILD_RUNNER_FINISH" --success
    ;;
  missing-artifact)
    "$PI_CHILD_RUNNER_FINISH" --success
    ;;
  crash)
    exit 17
    ;;
  slow)
    sleep 2
    ;;
esac
`, { mode: 0o755 });
  return { dir, bin, cwd, prompt };
}

function runHelper(fixture: TmuxFixture, args: string[] = [], env: Record<string, string> = {}) {
  return spawnSync(helper, [
    "--skill", "fixture-skill",
    "--task", "Write a small artifact",
    "--cwd", fixture.cwd,
    "--prompt-template", fixture.prompt,
    "--timeout", "1",
    ...args,
  ], {
    cwd: root,
    env: { ...process.env, PATH: `${fixture.bin}:${process.env.PATH}`, SHELL: "/bin/true", ...env },
    encoding: "utf8",
  });
}

function parseLaunch(stdout: string): Record<string, string> {
  const values: Record<string, string> = {};
  for (const line of stdout.trim().split(/\n/)) {
    const match = line.match(/^([A-Z0-9_]+)='(.*)'$/);
    if (match) values[match[1]] = match[2].replaceAll("'\\''", "'");
  }
  assert(values.ARTIFACT_PATH, "helper stdout should include ARTIFACT_PATH");
  assert(values.SUCCESS_SENTINEL, "helper stdout should include SUCCESS_SENTINEL");
  assert(values.FAILURE_SENTINEL, "helper stdout should include FAILURE_SENTINEL");
  assert.deepEqual(Object.keys(values).sort(), ["ARTIFACT_PATH", "FAILURE_SENTINEL", "SUCCESS_SENTINEL"].sort());
  return values;
}

async function testSuccess() {
  const fixture = await makeFixture();
  const result = runHelper(fixture, ["--artifact-dir", "reviews", "--model", "openai/example", "--provider", "openai", "--thinking", "low"]);
  assert.equal(result.status, 0, result.stderr);
  const launch = parseLaunch(result.stdout);
  assert.match(launch.ARTIFACT_PATH, /\.agents\/reviews\/pi-fixture-skill-write-a-small-artifact-\d{14}-\d+-[a-f0-9]+\.md$/);
  await stat(launch.SUCCESS_SENTINEL);
  assert.match(await readFile(launch.ARTIFACT_PATH, "utf8"), /# Artifact/);
  assert.doesNotMatch(result.stdout, /status_json|\.json/);
}

async function testValidation() {
  const fixture = await makeFixture();
  const result = runHelper({ ...fixture, prompt: join(fixture.dir, "missing.md") });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /prompt template does not exist/);
}

async function testMissingArtifactFailure() {
  const fixture = await makeFixture();
  const result = runHelper(fixture, [], { PI_FAKE_MODE: "missing-artifact" });
  assert.equal(result.status, 0, result.stderr);
  const launch = parseLaunch(result.stdout);
  await stat(launch.FAILURE_SENTINEL);
  assert.equal(await readFile(`${launch.FAILURE_SENTINEL}.reason`, "utf8"), "missing-artifact\n");
  await assert.rejects(() => stat(launch.ARTIFACT_PATH));
}

async function testChildExitWithoutFinishFailure() {
  const fixture = await makeFixture();
  const result = runHelper(fixture, [], { PI_FAKE_MODE: "crash" });
  assert.equal(result.status, 0, result.stderr);
  const launch = parseLaunch(result.stdout);
  await stat(launch.FAILURE_SENTINEL);
  assert.equal(await readFile(`${launch.FAILURE_SENTINEL}.reason`, "utf8"), "child-exit-without-finish\n");
}

async function testMissingTmuxDiagnostic() {
  const fixture = await makeFixture();
  await rm(join(fixture.bin, "tmux"));
  const result = spawnSync("/bin/bash", [helper,
    "--skill", "fixture-skill",
    "--task", "Write a small artifact",
    "--cwd", fixture.cwd,
    "--prompt-template", fixture.prompt,
    "--timeout", "1",
  ], {
    cwd: root,
    env: { ...process.env, PATH: fixture.bin },
    encoding: "utf8",
  });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /tmux is required and no other multiplexer is supported/);
}

async function testTmuxPaneFailureFinalizesStatus() {
  const fixture = await makeFixture();
  const result = runHelper(fixture, [], { PI_FAKE_TMUX_MODE: "fail" });
  assert.equal(result.status, 42);
  const launch = parseLaunch(result.stdout);
  await stat(launch.FAILURE_SENTINEL);
  assert.equal(await readFile(`${launch.FAILURE_SENTINEL}.reason`, "utf8"), "tmux-pane-failed\n");
  assert.match(await readFile(launch.ARTIFACT_PATH, "utf8"), /Reason: tmux-pane-failed/);
}

async function testConcurrentNamesDoNotCollide() {
  const fixture = await makeFixture();
  const run = () => new Promise<string>((resolve, reject) => {
    const child = spawn(helper, [
      "--skill", "fixture-skill",
      "--task", "Same task",
      "--cwd", fixture.cwd,
      "--prompt-template", fixture.prompt,
      "--timeout", "1",
    ], { env: { ...process.env, PATH: `${fixture.bin}:${process.env.PATH}` } });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("close", (code) => code === 0 ? resolve(stdout.trim()) : reject(new Error(stderr)));
  });
  const launches = (await Promise.all([run(), run()])).map(parseLaunch);
  assert.notEqual(launches[0].ARTIFACT_PATH, launches[1].ARTIFACT_PATH);
  const tmuxLog = await readFile(join(fixture.dir, "tmux.log"), "utf8");
  assert.match(tmuxLog, /split-window/);
}

async function testWaitForChildrenUsesSentinelPairs() {
  const dir = await mkdtemp(join(tmpdir(), "pi-coding-kit-wait-"));
  const success = join(dir, "child.success");
  const failure = join(dir, "child.failure");
  await writeFile(success, "");
  const result = spawnSync(waitHelper, ["--success", success, "--failure", failure, "--timeout", "1", "--poll", "1"], { encoding: "utf8" });
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /OVERALL='success'/);
  assert.match(result.stdout, /CHILD_1_STATUS='success'/);
  assert.doesNotMatch(result.stdout, /\{|status_json|run-id/);
}

await testSuccess();
await testValidation();
await testMissingArtifactFailure();
await testChildExitWithoutFinishFailure();
await testMissingTmuxDiagnostic();
await testTmuxPaneFailureFinalizesStatus();
await testConcurrentNamesDoNotCollide();
await testWaitForChildrenUsesSentinelPairs();
const policyWords = await readdir(join(root, "skills", "scripts"));
assert(policyWords.includes("start-bg-pane.sh"));
assert(policyWords.includes("wait-for-children.sh"));
assert(!policyWords.includes("run-skill-background.sh"));
assert(!policyWords.includes("tmux-managed-skills.tsv"));
console.log("tmux helper tests passed");
