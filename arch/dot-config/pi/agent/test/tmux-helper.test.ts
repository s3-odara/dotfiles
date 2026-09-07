import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, readdir, rm, stat, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawn, spawnSync } from "node:child_process";
import { agentNames, promptPath, startPanePath, waitPath } from "../extension-src/agents/config.ts";
import { parseLauncherOutput } from "../extension-src/agents/index.ts";

// No real Pi/model or tmux server is started. Run the actual launcher, generated
// runner/finish scripts and waiter with a synchronous fake tmux and a fake Pi.
const fixtures: string[] = [];
async function makeFixture() {
  const dir = await mkdtemp(join(tmpdir(), "pi-agent-tmux-"));
  fixtures.push(dir);
  const bin = join(dir, "bin");
  const cwd = join(dir, "work ' space");
  await mkdir(bin);
  await mkdir(cwd);
  await writeFile(join(cwd, "source.txt"), "unchanged\n");
  await writeFile(join(bin, "tmux"), `#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  display-message) printf 'parent\\n' ;;
  list-windows) if [[ "\${PI_TEST_WINDOW_MISSING:-}" != 1 ]]; then printf 'agent\\n'; fi ;;
  has-session|new-session|kill-pane|select-layout) : ;;
  split-window|new-window)
    if [[ "\${PI_TEST_TMUX_FAIL:-}" == 1 ]]; then echo 'pane failed' >&2; exit 42; fi
    [[ "\${@: -2:1}" == bash ]] || { echo 'runner must use direct tmux argv, not a shell command string' >&2; exit 43; }
    command="\${@: -1}"
    TMUX_PANE='%7' bash "$command" || true
    printf 'parent:1.2 %%7\\n'
    ;;
  *) exit 9 ;;
esac
`, { mode: 0o755 });
  await writeFile(join(bin, "pi"), `#!/usr/bin/env bash
set -euo pipefail
[[ "$PI_AGENT_CHILD" == 1 ]]
printf '%s\\0' "$@" >"${dir}/pi.args"
# Even a direct bash call to the launcher is rejected in the child environment.
if "$PI_TEST_LAUNCHER" >"${dir}/nested.out" 2>"${dir}/nested.err"; then exit 99; fi
case "\${PI_TEST_MODE:-success}" in
  success)
    printf '# %s report\\n\\nStatus: complete\\n' "$PI_AGENT_ROLE" >"$PI_AGENT_ARTIFACT_PATH"
    "$PI_AGENT_FINISH" --success
    ;;
  missing-artifact) "$PI_AGENT_FINISH" --success ;;
  failure) "$PI_AGENT_FINISH" --failure 'test failure' ;;
  crash) exit 17 ;;
  slow)
    touch "${dir}/ready"
    sleep 2
    printf '# report\\n' >"$PI_AGENT_ARTIFACT_PATH"
    "$PI_AGENT_FINISH" --success
    ;;
esac
`, { mode: 0o755 });
  const env: Record<string, string | undefined> = { ...process.env, PATH: `${bin}:${process.env.PATH}`, SHELL: "/bin/true", PI_TEST_LAUNCHER: startPanePath };
  delete env.PI_AGENT_CHILD;
  delete env.PI_CHILD_RUNNER_SKILL;
  return { dir, bin, cwd, env };
}
type Fixture = Awaited<ReturnType<typeof makeFixture>>;
function args(f: Fixture, agent = "reviewer") {
  return ["--agent", agent, "--task", "A concrete assignment with context", "--cwd", f.cwd,
    "--role-prompt", promptPath(agent as typeof agentNames[number])];
}
function run(f: Fixture, extra: string[] = [], env = {}) {
  return spawnSync(startPanePath, [...args(f), ...extra], { env: { ...f.env, ...env }, encoding: "utf8", timeout: 10000 });
}
function launchPaths(stdout: string) {
  const paths = parseLauncherOutput(stdout);
  assert.deepEqual(Object.keys(paths).sort(), ["ARTIFACT_PATH", "FAILURE_SENTINEL", "SUCCESS_SENTINEL"]);
  return paths;
}

try {
  for (const agent of agentNames) {
    const f = await makeFixture();
    const result = spawnSync(startPanePath, [...args(f, agent), "--model", "test-model", "--provider", "test-provider", "--thinking", "low"], {
      env: { ...f.env, PI_TEST_WINDOW_MISSING: agent === "reviewer" ? "1" : "0" }, encoding: "utf8", timeout: 10000,
    });
    assert.equal(result.status, 0, result.stderr);
    const paths = launchPaths(result.stdout);
    await stat(paths.SUCCESS_SENTINEL);
    assert.match(await readFile(paths.ARTIFACT_PATH, "utf8"), new RegExp(`# ${agent} report`));
    assert.equal(await readFile(join(f.cwd, "source.txt"), "utf8"), "unchanged\n");
    assert.match(await readFile(join(f.dir, "nested.err"), "utf8"), /subagents cannot launch subagents/);
    const piArgs = (await readFile(join(f.dir, "pi.args"), "utf8")).split("\0").slice(0, -1);
    assert(piArgs.includes("--no-skills"));
    assert(piArgs.includes("--no-prompt-templates"));
    assert.equal(piArgs[piArgs.indexOf("--exclude-tools") + 1], "run_agent,run_skill");
    assert(!piArgs.includes("--prompt-template"));
    assert(!piArgs.includes("--no-extensions"), "MCP/LSP and other tools stay available");
    const system = piArgs[piArgs.indexOf("--append-system-prompt") + 1];
    assert.match(system, /You are a subagent, not the main agent/);
    assert.match(system, /Never delegate/);
    assert(system.includes((await readFile(promptPath(agent), "utf8")).trimEnd()), "role body is actually injected, not merely registered");
    assert.match(piArgs.at(-1)!, /Primary artifact path:/);
    assert.match(piArgs.at(-1)!, /A concrete assignment with context/);
    assert.equal(piArgs[piArgs.indexOf("--model") + 1], "test-model");
    assert.equal(piArgs[piArgs.indexOf("--provider") + 1], "test-provider");
    assert.equal(piArgs[piArgs.indexOf("--thinking") + 1], "low");
  }

  const invalid = await makeFixture();
  for (const agent of ["planner", "review-orchestrator", "plan-reviewer", "unknown"]) {
    const result = run(invalid, ["--agent", agent]);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /invalid --agent role/);
  }
  const missingPrompt = run(invalid, ["--role-prompt", join(invalid.dir, "missing.md")]);
  assert.notEqual(missingPrompt.status, 0);
  assert.match(missingPrompt.stderr, /role prompt does not exist/);
  for (const marker of ["PI_AGENT_CHILD", "PI_CHILD_RUNNER_SKILL"]) {
    const result = run(invalid, [], { [marker]: "1" });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /subagents cannot launch subagents/);
  }
  await assert.rejects(stat(join(invalid.cwd, ".agents")), "invalid/nested requests do not create artifacts or panes");

  for (const [mode, reason] of [["missing-artifact", "missing-artifact"], ["crash", "child-exit-without-finish"], ["failure", "test failure"]]) {
    const f = await makeFixture();
    const result = run(f, [], { PI_TEST_MODE: mode });
    assert.equal(result.status, 0, result.stderr);
    const paths = launchPaths(result.stdout);
    await stat(paths.FAILURE_SENTINEL);
    await assert.rejects(stat(paths.SUCCESS_SENTINEL));
    assert.equal(await readFile(`${paths.FAILURE_SENTINEL}.reason`, "utf8"), `${reason}\n`);
  }
  const paneFailure = await makeFixture();
  const badPane = run(paneFailure, [], { PI_TEST_TMUX_FAIL: "1" });
  assert.equal(badPane.status, 42);
  const badPaths = launchPaths(badPane.stdout);
  assert.match(await readFile(badPaths.ARTIFACT_PATH, "utf8"), /tmux-pane-failed/);
  await stat(badPaths.FAILURE_SENTINEL);

  const noTmux = await makeFixture();
  await rm(join(noTmux.bin, "tmux"));
  const missing = spawnSync("/bin/bash", [startPanePath, ...args(noTmux)], { env: { ...noTmux.env, PATH: noTmux.bin }, encoding: "utf8" });
  assert.notEqual(missing.status, 0);
  assert.match(missing.stderr, /tmux is required/);

  const lock = await makeFixture();
  const startLocked = () => new Promise<string>((resolve, reject) => {
    const child = spawn(startPanePath, [...args(lock, "implementer"), "--workspace-lock"], { env: { ...lock.env, PI_TEST_MODE: "slow" } });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (data: unknown) => { stdout += String(data); });
    child.stderr.on("data", (data: unknown) => { stderr += String(data); });
    child.on("error", reject);
    child.on("close", (code: number | null) => code === 0 ? resolve(stdout) : reject(new Error(stderr)));
  });
  const first = startLocked();
  // Wait for fake Pi to start inside the acquired lock, not a scheduling guess.
  let ready = false;
  for (let i = 0; i < 100; i++) {
    try { await stat(join(lock.dir, "ready")); ready = true; break; } catch { await new Promise((r) => setTimeout(r, 20)); }
  }
  assert(ready, "first implementer should acquire the workspace lock");
  const [one, two] = (await Promise.all([first, startLocked()])).map(launchPaths);
  assert.notEqual(one.ARTIFACT_PATH, two.ARTIFACT_PATH);
  await stat(one.SUCCESS_SENTINEL);
  assert.equal(await readFile(`${two.FAILURE_SENTINEL}.reason`, "utf8"), "workspace-lock-held\n");
  assert.match(await readFile(two.ARTIFACT_PATH, "utf8"), /workspace-lock-held/);
  const statusFiles = await readdir(join(lock.cwd, ".agents/status"));
  assert.equal(statusFiles.filter((name: string) => name.endsWith(".runner.sh")).length, 2, "no grandchildren were launched");

  for (const state of ["success", "failure", "timeout"]) {
    const f = await makeFixture();
    const success = join(f.dir, "done.success");
    const failure = join(f.dir, "done.failure");
    if (state !== "timeout") await writeFile(state === "success" ? success : failure, "");
    const result = spawnSync(waitPath, ["--success", success, "--failure", failure, "--timeout", "1", "--poll", "1"], { encoding: "utf8", timeout: 5000 });
    assert.equal(result.status, state === "success" ? 0 : 1);
    assert.match(result.stdout, new RegExp(`CHILD_1_STATUS='${state}'`));
  }
} finally {
  await Promise.all(fixtures.map((dir) => rm(dir, { recursive: true, force: true })));
}
console.log("tmux agent helper tests passed");
