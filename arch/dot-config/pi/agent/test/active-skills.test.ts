import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, readdir, stat, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawn, spawnSync } from "node:child_process";

const root = new URL("..", import.meta.url).pathname;

const skills = [
  { name: "implementer", artifactDir: "impl-reports", readonly: false },
  { name: "debugger", artifactDir: "reviews", readonly: true },
  { name: "review-orchestrator", artifactDir: "reviews", readonly: true },
];

type SkillFixture = { dir: string; bin: string; cwd: string };

async function makeFixture(): Promise<SkillFixture> {
  const dir = await mkdtemp(join(tmpdir(), "pi-coding-kit-active-"));
  const bin = join(dir, "bin");
  const cwd = join(dir, "work");
  await mkdir(bin);
  await mkdir(cwd);
  await writeFile(join(cwd, "source.txt"), "unchanged\n");
  await writeFile(join(bin, "tmux"), `#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" != "new-session" || "$2" != "-d" || "$3" != "-s" ]]; then
  printf 'unsupported fake tmux invocation: %s\\n' "$*" >&2
  exit 9
fi
session="$4"
command="$5"
printf '%s\\n' "$session" >>"${dir}/sessions.log"
if [[ "${'${FAKE_TMUX_PRESERVE_STARTED:-}'}" == "1" ]]; then
  exit 0
fi
bash "$command" || true
`, { mode: 0o755 });
  await writeFile(join(bin, "pi"), `#!/usr/bin/env bash
set -euo pipefail
case "${'${PI_FAKE_MODE:-success}'}" in
  success)
    if [[ "$PI_CHILD_RUNNER_SKILL" == "implementer" ]]; then
      printf '# Implementation Report:\\n\\nChanged files: none in fixture.\\n' >"$PI_CHILD_RUNNER_ARTIFACT_PATH"
    else
      printf '# %s artifact\\n' "$PI_CHILD_RUNNER_SKILL" >"$PI_CHILD_RUNNER_ARTIFACT_PATH"
    fi
    ;;
  mixed)
    printf '# %s artifact\\n\\nRetained finding from %s.\\n' "$PI_CHILD_RUNNER_SKILL" "$PI_CHILD_RUNNER_SKILL" >"$PI_CHILD_RUNNER_ARTIFACT_PATH"
    ;;
  slow)
    sleep 2
    printf '# Implementation Report:\\n\\nSlow fixture.\\n' >"$PI_CHILD_RUNNER_ARTIFACT_PATH"
    ;;
  crash)
    exit 17
    ;;
  missing-artifact)
    :
    ;;
esac
`, { mode: 0o755 });
  return { dir, bin, cwd };
}

function wrapperPath(skill: string) {
  return join(root, "skills", skill, "scripts", "spawn-tmux-child.sh");
}

function statusPathFromStdout(stdout: string): string {
  const statusPath = stdout.trim().split(/\n/).find((line) => line.endsWith(".json"));
  assert(statusPath, "wrapper stdout should include a status JSON path");
  return statusPath;
}

async function testSkillMetadataAndWrappers() {
  for (const skill of skills) {
    const markdown = await readFile(join(root, "skills", skill.name, "SKILL.md"), "utf8");
    assert.match(markdown, /^---\n[\s\S]*?\n---\n/, `${skill.name} must have YAML frontmatter`);
    const frontmatter = markdown.match(/^---\n([\s\S]*?)\n---\n/)[1];
    assert.match(frontmatter, new RegExp(`^name:\\s*${skill.name}$`, "m"));
    assert.match(frontmatter, /^description:\s*\S.+$/m);
    assert.match(markdown, /\.agents\//);
    if (skill.readonly) assert.match(markdown, /Do not edit|should not fix code/);
    await stat(wrapperPath(skill.name));
  }
}

async function testImplementerAndDebuggerArtifacts() {
  const fixture = await makeFixture();
  for (const skill of skills.slice(0, 2)) {
    const result = spawnSync(wrapperPath(skill.name), ["--task", `Run ${skill.name}`, "--cwd", fixture.cwd, "--timeout", "1"], {
      cwd: root,
      env: { ...process.env, PATH: `${fixture.bin}:${process.env.PATH}` },
      encoding: "utf8",
    });
    assert.equal(result.status, 0, result.stderr);
    const status = JSON.parse(await readFile(statusPathFromStdout(result.stdout), "utf8"));
    assert.equal(status.skill, skill.name);
    assert.equal(status.status, "success");
    assert.match(status.artifact_path, new RegExp(`\\.agents/${skill.artifactDir}/`));
    if (skill.name === "implementer") {
      assert.equal(status.lock_enabled, true);
      assert.match(status.lock_key, /^workspace-/);
      assert.match(status.lock_file, /\.agents\/locks\/workspace-.*\.lock$/);
      assert.match(await readFile(status.artifact_path, "utf8"), /^# Implementation Report:/);
    }
  }
}

async function testImplementerLockTimeout() {
  const fixture = await makeFixture();
  const run = (timeout: string) => new Promise<string>((resolve, reject) => {
    const child = spawn(wrapperPath("implementer"), ["--task", "Same workspace", "--cwd", fixture.cwd, "--timeout", "3"], {
      env: { ...process.env, PATH: `${fixture.bin}:${process.env.PATH}`, PI_FAKE_MODE: "slow", PI_IMPLEMENTER_LOCK_TIMEOUT: timeout },
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("close", (code) => code === 0 ? resolve(stdout) : reject(new Error(stderr)));
  });
  const firstPromise = run("2");
  // Give the first fake child a moment to enter the runner and acquire the
  // workspace lock; the test is about lock behavior, not process scheduling.
  await new Promise((resolve) => setTimeout(resolve, 250));
  const [first, second] = await Promise.all([firstPromise, run("0")]);
  const statuses = await Promise.all([first, second].map(async (stdout) => JSON.parse(await readFile(statusPathFromStdout(stdout), "utf8"))));
  assert(statuses.some((status) => status.status === "success"));
  const locked = statuses.find((status) => status.failure_reason === "lock-timeout");
  assert(locked, "one concurrent implementer should fail clearly on the workspace lock");
  assert.match(await readFile(locked.artifact_path, "utf8"), /Reason: lock-timeout/);
}

async function testReviewOrchestratorAggregatesChildDiagnostics() {
  const fixture = await makeFixture();
  const result = spawnSync(wrapperPath("review-orchestrator"), ["--task", "Review target", "--cwd", fixture.cwd, "--timeout", "1"], {
    cwd: root,
    env: {
      ...process.env,
      PATH: `${fixture.bin}:${process.env.PATH}`,
      PI_FAKE_MODE: "missing-artifact",
    },
    encoding: "utf8",
  });
  assert.equal(result.status, 0, result.stderr);
  const artifact = result.stdout.trim().split(/\n/).find((line) => line.endsWith(".md"));
  await stat(artifact);
  const report = await readFile(artifact, "utf8");
  assert.match(report, /^# Review Orchestrator Report/);
  assert.match(report, /code-reviewer: failure \(missing-artifact\)/);
  assert.match(report, /No retained findings: no successful child review artifact was available\./);
}

async function testReviewOrchestratorSuccessRetainsFindingsAndUniquePaths() {
  const fixture = await makeFixture();
  const run = () => spawnSync(wrapperPath("review-orchestrator"), ["--task", "Review target", "--cwd", fixture.cwd, "--timeout", "1"], {
    cwd: root,
    env: {
      ...process.env,
      PATH: `${fixture.bin}:${process.env.PATH}`,
    },
    encoding: "utf8",
  });
  const first = run();
  const second = run();
  assert.equal(first.status, 0, first.stderr);
  assert.equal(second.status, 0, second.stderr);
  const artifacts = [first, second].map((result) => result.stdout.trim().split(/\n/).find((line) => line.endsWith(".md")));
  assert.notEqual(artifacts[0], artifacts[1], "same-second orchestrator runs should not collide");
  const report = await readFile(artifacts[0], "utf8");
  assert.match(report, /## Retained Findings/);
  assert.match(report, /### code-reviewer/);
}

async function testReviewOrchestratorLaunchFailure() {
  const fixture = await makeFixture();
  const result = spawnSync(wrapperPath("review-orchestrator"), ["--task", "Review target", "--cwd", fixture.cwd, "--timeout", "1", "--pi-bin", "missing-pi"], {
    cwd: root,
    env: { ...process.env, PATH: `${fixture.bin}:${process.env.PATH}` },
    encoding: "utf8",
  });
  assert.equal(result.status, 0, result.stderr);
  const artifact = result.stdout.trim().split(/\n/).find((line) => line.endsWith(".md"));
  const report = await readFile(artifact, "utf8");
  assert.match(report, /code-reviewer: launch-failed/);
  assert.match(report, /code-reviewer: missing status JSON/);
}

async function testReviewOrchestratorTimeout() {
  const fixture = await makeFixture();
  const result = spawnSync(wrapperPath("review-orchestrator"), ["--task", "Review target", "--cwd", fixture.cwd, "--timeout", "1"], {
    cwd: root,
    env: { ...process.env, PATH: `${fixture.bin}:${process.env.PATH}`, PI_FAKE_MODE: "slow" },
    encoding: "utf8",
  });
  assert.equal(result.status, 0, result.stderr);
  const artifact = result.stdout.trim().split(/\n/).find((line) => line.endsWith(".md"));
  const report = await readFile(artifact, "utf8");
  assert.match(report, /code-reviewer: failure \(timeout\)/);
}

async function testReviewOrchestratorReportsPollingTimeoutWhileStarted() {
  const fixture = await makeFixture();
  const result = spawnSync(wrapperPath("review-orchestrator"), ["--task", "Review target", "--cwd", fixture.cwd, "--timeout", "1"], {
    cwd: root,
    env: { ...process.env, PATH: `${fixture.bin}:${process.env.PATH}`, FAKE_TMUX_PRESERVE_STARTED: "1" },
    encoding: "utf8",
  });
  assert.equal(result.status, 0, result.stderr);
  const artifact = result.stdout.trim().split(/\n/).find((line) => line.endsWith(".md"));
  const report = await readFile(artifact, "utf8");
  assert.match(report, /code-reviewer: failure \(timeout\)/);
  assert.doesNotMatch(report, /code-reviewer: started/, "nonterminal child status should be reported as a timeout diagnostic");
  assert.match(report, /No retained findings: no successful child review artifact was available\./);
}

async function testReviewOrchestratorPreservesBackslashEscapesInStatusJson() {
  const fixture = await makeFixture();
  const escapedCwd = join(fixture.dir, "work\\tb");
  await mkdir(escapedCwd);
  const result = spawnSync(wrapperPath("review-orchestrator"), ["--task", "Review target", "--cwd", escapedCwd, "--timeout", "1"], {
    cwd: root,
    env: { ...process.env, PATH: `${fixture.bin}:${process.env.PATH}` },
    encoding: "utf8",
  });
  assert.equal(result.status, 0, result.stderr);
  const artifact = result.stdout.trim().split(/\n/).find((line) => line.endsWith(".md"));
  const report = await readFile(artifact, "utf8");
  assert.match(report, /work\\tb/, "literal backslash-t in status JSON paths must not decode as a tab");
  assert.doesNotMatch(report, /work\tb/);
}

async function testReviewOrchestratorRetainedFindingsAndForwardedPaneFlags() {
  const fixture = await makeFixture();
  const result = spawnSync(wrapperPath("review-orchestrator"), ["--task", "Review target", "--cwd", fixture.cwd, "--timeout", "1", "--keep-pane", "--auto-exit"], {
    cwd: root,
    env: {
      ...process.env,
      PATH: `${fixture.bin}:${process.env.PATH}`,
      PI_FAKE_MODE: "mixed",
    },
    encoding: "utf8",
  });
  assert.equal(result.status, 0, result.stderr);
  const artifact = result.stdout.trim().split(/\n/).find((line) => line.endsWith(".md"));
  const report = await readFile(artifact, "utf8");
  assert.match(report, /code-reviewer: success/);
  assert.match(report, /Retained finding from code-reviewer/);

  const statusDir = join(fixture.cwd, ".agents", "status");
  const statusFiles = (await readdir(statusDir)).filter((name) => name.endsWith(".json"));
  const statuses = await Promise.all(statusFiles.map(async (name) => JSON.parse(await readFile(join(statusDir, name), "utf8"))));
  const reviewerStatus = statuses.find((status) => status.skill === "code-reviewer");
  assert(reviewerStatus, "code-reviewer status should be present");
  assert.equal(reviewerStatus.keep_pane, true);
  assert.equal(reviewerStatus.auto_exit, true);
}

await testSkillMetadataAndWrappers();
await testImplementerAndDebuggerArtifacts();
await testImplementerLockTimeout();
await testReviewOrchestratorAggregatesChildDiagnostics();
await testReviewOrchestratorSuccessRetainsFindingsAndUniquePaths();
await testReviewOrchestratorLaunchFailure();
await testReviewOrchestratorTimeout();
await testReviewOrchestratorReportsPollingTimeoutWhileStarted();
await testReviewOrchestratorPreservesBackslashEscapesInStatusJson();
await testReviewOrchestratorRetainedFindingsAndForwardedPaneFlags();

console.log("active skill tests passed");
