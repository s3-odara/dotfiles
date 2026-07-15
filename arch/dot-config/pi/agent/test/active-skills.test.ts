import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, stat, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawn, spawnSync } from "node:child_process";

const root = new URL("..", import.meta.url).pathname;

const skills = [
  { name: "implementer", artifactDir: "impl-reports", readonly: false },
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
case "$1" in
  display-message) printf 'parent\\n' ;;
  list-windows) printf 'agent\\n' ;;
  has-session|new-session|kill-pane) : ;;
  split-window|new-window)
    printf '%s\\n' "$1" >>"${dir}/panes.log"
    if [[ "${'${FAKE_TMUX_PRESERVE_STARTED:-}'}" == "1" ]]; then printf 'parent:1.2 %%9\\n'; exit 0; fi
    command="${'${@: -1}'}"
    TMUX_PANE='%9' bash "$command" || true
    printf 'parent:1.2 %%9\\n'
    ;;
  *) printf 'unsupported fake tmux invocation: %s\\n' "$*" >&2; exit 9 ;;
esac
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
    "$PI_CHILD_RUNNER_FINISH" --success
    ;;
  mixed)
    printf '# %s artifact\\n\\nRetained finding from %s.\\n' "$PI_CHILD_RUNNER_SKILL" "$PI_CHILD_RUNNER_SKILL" >"$PI_CHILD_RUNNER_ARTIFACT_PATH"
    "$PI_CHILD_RUNNER_FINISH" --success
    ;;
  slow)
    sleep 2
    printf '# Implementation Report:\\n\\nSlow fixture.\\n' >"$PI_CHILD_RUNNER_ARTIFACT_PATH"
    "$PI_CHILD_RUNNER_FINISH" --success
    ;;
  crash)
    exit 17
    ;;
  missing-artifact)
    "$PI_CHILD_RUNNER_FINISH" --success
    ;;
esac
`, { mode: 0o755 });
  return { dir, bin, cwd };
}

function helperPath() {
  return join(root, "skills", "scripts", "start-bg-pane.sh");
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

async function testSkillMetadataAndHelpers() {
  for (const skill of skills) {
    const markdown = await readFile(join(root, "skills", skill.name, "SKILL.md"), "utf8");
    assert.match(markdown, /^---\n[\s\S]*?\n---\n/, `${skill.name} must have YAML frontmatter`);
    const frontmatter = markdown.match(/^---\n([\s\S]*?)\n---\n/)[1];
    assert.match(frontmatter, new RegExp(`^name:\\s*${skill.name}$`, "m"));
    assert.match(frontmatter, /^description:\s*\S.+$/m);
    assert.match(markdown, /\.agents\//);
    if (skill.readonly) assert.match(markdown, /Do not edit|should not fix code/);
    if (skill.name === "review-orchestrator") {
      assert.match(markdown, /Use the `explorer` result/);
      assert.match(markdown, /Delegate multiple tasks to `code-reviewer`/);
      assert.match(markdown, /Wait for the delegated reviews to finish/);
      assert.match(markdown, /Primary artifact path/);
      assert.match(markdown, /missing artifacts, non-success statuses, timeouts, and child launch failures/);
    }
  }
}

async function testImplementerArtifact() {
  const fixture = await makeFixture();
  const skill = skills[0];
  const args = ["--skill", skill.name, "--artifact-dir", skill.artifactDir, "--prompt-template", join(root, "skills", skill.name, "SKILL.md"), "--task", `Run ${skill.name}`, "--cwd", fixture.cwd, "--timeout", "1", "--workspace-lock"];
  const result = spawnSync(helperPath(), args, {
    cwd: root,
    env: { ...process.env, PATH: `${fixture.bin}:${process.env.PATH}`, SHELL: "/bin/true" },
    encoding: "utf8",
  });
  assert.equal(result.status, 0, result.stderr);
  const launch = parseLaunch(result.stdout);
  await stat(launch.SUCCESS_SENTINEL);
  assert.match(launch.ARTIFACT_PATH, new RegExp(`\\.agents/${skill.artifactDir}/`));
  assert.match(await readFile(launch.ARTIFACT_PATH, "utf8"), /^# Implementation Report:/);
}

async function testImplementerWorkspaceLock() {
  const fixture = await makeFixture();
  const run = () => new Promise<string>((resolve, reject) => {
    const child = spawn(helperPath(), ["--skill", "implementer", "--artifact-dir", "impl-reports", "--prompt-template", join(root, "skills", "implementer", "SKILL.md"), "--task", "Same workspace", "--cwd", fixture.cwd, "--timeout", "3", "--workspace-lock"], {
      env: { ...process.env, PATH: `${fixture.bin}:${process.env.PATH}`, SHELL: "/bin/true", PI_FAKE_MODE: "slow" },
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("close", (code) => code === 0 ? resolve(stdout) : reject(new Error(stderr)));
  });
  const firstPromise = run();
  // Give the first fake child a moment to enter the runner and acquire the
  // workspace lock; the test is about lock behavior, not process scheduling.
  await new Promise((resolve) => setTimeout(resolve, 250));
  const [first, second] = await Promise.all([firstPromise, run()]);
  const launches = [first, second].map(parseLaunch);
  assert(launches.some((launch) => launch.SUCCESS_SENTINEL));
  let locked: Record<string, string> | undefined;
  for (const launch of launches) {
    try {
      if (await readFile(`${launch.FAILURE_SENTINEL}.reason`, "utf8") === "workspace-lock-held\n") locked = launch;
    } catch {}
  }
  assert(locked, "one concurrent implementer should fail clearly on the workspace lock");
  assert.match(await readFile(locked.ARTIFACT_PATH, "utf8"), /Reason: workspace-lock-held/);
}

async function testReviewOrchestratorRunsAsNormalSkill() {
  const fixture = await makeFixture();
  const result = spawnSync(helperPath(), ["--skill", "review-orchestrator", "--artifact-dir", "reviews", "--prompt-template", join(root, "skills", "review-orchestrator", "SKILL.md"), "--task", "Review target", "--cwd", fixture.cwd, "--timeout", "1"], {
    cwd: root,
    env: { ...process.env, PATH: `${fixture.bin}:${process.env.PATH}`, SHELL: "/bin/true" },
    encoding: "utf8",
  });
  assert.equal(result.status, 0, result.stderr);
  const launch = parseLaunch(result.stdout);
  await stat(launch.SUCCESS_SENTINEL);
  assert.match(launch.ARTIFACT_PATH, /\.agents\/reviews\//);
  assert.match(await readFile(launch.ARTIFACT_PATH, "utf8"), /^# review-orchestrator artifact/);
}

await testSkillMetadataAndHelpers();
await testImplementerArtifact();
await testImplementerWorkspaceLock();
await testReviewOrchestratorRunsAsNormalSkill();

console.log("active skill tests passed");
