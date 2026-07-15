import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, readdir, stat, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawn, spawnSync } from "node:child_process";

const root = new URL("..", import.meta.url).pathname;

const skills = [
  { name: "explorer", artifactDir: "research", readonly: true },
  { name: "internet-researcher", artifactDir: "research", readonly: true },
  { name: "code-reviewer", artifactDir: "reviews", readonly: true },
  { name: "plan-reviewer", artifactDir: "reviews", readonly: true },
];

type Skill = (typeof skills)[number];
type SkillFixture = { dir: string; bin: string; cwd: string };

async function makeFixture(): Promise<SkillFixture> {
  const dir = await mkdtemp(join(tmpdir(), "pi-coding-kit-skills-"));
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
    command="${'${@: -1}'}"
    TMUX_PANE='%8' bash "$command" || true
    printf 'parent:1.2 %%8\\n'
    ;;
  *) printf 'unsupported fake tmux invocation: %s\\n' "$*" >&2; exit 9 ;;
esac
`, { mode: 0o755 });
  await writeFile(join(bin, "pi"), `#!/usr/bin/env bash
set -euo pipefail
case "${'${PI_FAKE_MODE:-success}'}" in
  success)
    printf '# %s artifact\\n\\nTask file: %s\\n' "$PI_CHILD_RUNNER_SKILL" "$PI_CHILD_RUNNER_TASK_FILE" >"$PI_CHILD_RUNNER_ARTIFACT_PATH"
    "$PI_CHILD_RUNNER_FINISH" --success
    ;;
  mcp-unavailable)
    # This fixture models the internet-researcher prompt's required behavior
    # when web MCP tools are absent. It still writes the requested artifact so
    # the shared helper success path remains covered separately from the
    # generic missing-artifact failure path.
    printf '# MCP Web Tools Unavailable\\n\\nConfigured web MCP tools were not available; research is limited.\\n' >"$PI_CHILD_RUNNER_ARTIFACT_PATH"
    "$PI_CHILD_RUNNER_FINISH" --success
    ;;
  missing-artifact)
    "$PI_CHILD_RUNNER_FINISH" --success
    ;;
esac
`, { mode: 0o755 });
  return { dir, bin, cwd };
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

function helperPath() {
  return join(root, "skills", "scripts", "start-bg-pane.sh");
}

function slug(value: string) {
  return value.replaceAll("_", "-");
}

async function runHelper(fixture: SkillFixture, skill: Skill, extraEnv: Record<string, string> = {}) {
  const result = spawnSync(helperPath(), [
    "--skill", skill.name,
    "--artifact-dir", skill.artifactDir,
    "--prompt-template", join(root, "skills", skill.name, "SKILL.md"),
    "--task", `Check ${skill.name}`,
    "--cwd", fixture.cwd,
    "--timeout", "1",
  ], {
    cwd: root,
    env: { ...process.env, PATH: `${fixture.bin}:${process.env.PATH}`, SHELL: "/bin/true", ...extraEnv },
    encoding: "utf8",
  });
  assert.equal(result.status, 0, result.stderr);
  const launch = parseLaunch(result.stdout);
  assert.match(launch.ARTIFACT_PATH, new RegExp(`\\.agents/${skill.artifactDir}/pi-${skill.name}-check-${slug(skill.name)}-\\d{14}-\\d+-[a-f0-9]+\\.md$`));
  await stat(launch.SUCCESS_SENTINEL);
  assert.match(await readFile(launch.ARTIFACT_PATH, "utf8"), new RegExp(`# ${skill.name} artifact`));
  assert.equal(await readFile(join(fixture.cwd, "source.txt"), "utf8"), "unchanged\n");
  return launch;
}

async function testSkillMetadataAndHelpers() {
  for (const skill of skills) {
    const markdown = await readFile(join(root, "skills", skill.name, "SKILL.md"), "utf8");
    assert.match(markdown, /^---\n[\s\S]*?\n---\n/, `${skill.name} must have YAML frontmatter`);
    const frontmatter = markdown.match(/^---\n([\s\S]*?)\n---\n/)[1];
    assert.match(frontmatter, new RegExp(`^name:\\s*${skill.name}$`, "m"), `${skill.name} frontmatter must declare its skill name`);
    assert.match(frontmatter, /^description:\s*\S.+$/m, `${skill.name} frontmatter must declare a non-empty description`);
    assert.match(markdown, /Primary artifact path/);
    assert.match(markdown, /\.agents\//);
    if (skill.readonly) assert.match(markdown, /Do not edit|Do not edit project files|Do not edit files/);
  }
}

async function testHelpersProduceCanonicalArtifacts() {
  const fixture = await makeFixture();
  for (const skill of skills) await runHelper(fixture, skill);
  const panes = (await readFile(join(fixture.dir, "panes.log"), "utf8")).trim().split(/\n/);
  assert.equal(panes.length, skills.length);
}

async function testConcurrentReadonlyHelpersDoNotCollide() {
  const fixture = await makeFixture();
  const selected = skills.filter((skill) => skill.readonly).slice(0, 2);
  const run = (skill) => new Promise((resolve, reject) => {
    const child = spawn(helperPath(), [
      "--skill", skill.name,
      "--artifact-dir", skill.artifactDir,
      "--prompt-template", join(root, "skills", skill.name, "SKILL.md"),
      "--task", "Concurrent read check",
      "--cwd", fixture.cwd,
      "--timeout", "1",
    ], { env: { ...process.env, PATH: `${fixture.bin}:${process.env.PATH}`, SHELL: "/bin/true" } });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("close", (code) => code === 0 ? resolve(stdout.trim()) : reject(new Error(stderr)));
  });
  const statuses = await Promise.all(selected.map((skill) => run(skill)));
  assert.notEqual(statuses[0], statuses[1]);
}

async function testInternetResearcherUnavailableMcpWritesFailureArtifact() {
  const fixture = await makeFixture();
  const result = spawnSync(helperPath(), [
    "--skill", "internet-researcher",
    "--artifact-dir", "research",
    "--prompt-template", join(root, "skills", "internet-researcher", "SKILL.md"),
    "--task", "Research with unavailable MCP tools",
    "--cwd", fixture.cwd,
    "--timeout", "1",
  ], {
    cwd: root,
    env: { ...process.env, PATH: `${fixture.bin}:${process.env.PATH}`, SHELL: "/bin/true", PI_FAKE_MODE: "missing-artifact" },
    encoding: "utf8",
  });
  assert.equal(result.status, 0, result.stderr);
  const launch = parseLaunch(result.stdout);
  await stat(launch.FAILURE_SENTINEL);
  assert.equal(await readFile(`${launch.FAILURE_SENTINEL}.reason`, "utf8"), "missing-artifact\n");
  await assert.rejects(() => stat(launch.ARTIFACT_PATH));
}

async function testInternetResearcherUnavailableMcpWritesLimitationArtifact() {
  const fixture = await makeFixture();
  const result = spawnSync(helperPath(), [
    "--skill", "internet-researcher",
    "--artifact-dir", "research",
    "--prompt-template", join(root, "skills", "internet-researcher", "SKILL.md"),
    "--task", "Research with unavailable MCP tools",
    "--cwd", fixture.cwd,
    "--timeout", "1",
  ], {
    cwd: root,
    env: { ...process.env, PATH: `${fixture.bin}:${process.env.PATH}`, SHELL: "/bin/true", PI_FAKE_MODE: "mcp-unavailable" },
    encoding: "utf8",
  });
  assert.equal(result.status, 0, result.stderr);
  const launch = parseLaunch(result.stdout);
  await stat(launch.SUCCESS_SENTINEL);
  assert.match(launch.ARTIFACT_PATH, /\.agents\/research\/pi-internet-researcher-/);
  assert.match(await readFile(launch.ARTIFACT_PATH, "utf8"), /MCP Web Tools Unavailable/);
}

await testSkillMetadataAndHelpers();
await testHelpersProduceCanonicalArtifacts();
await testConcurrentReadonlyHelpersDoNotCollide();
await testInternetResearcherUnavailableMcpWritesFailureArtifact();
await testInternetResearcherUnavailableMcpWritesLimitationArtifact();

const skillEntries = await readdir(join(root, "skills"));
for (const skill of skills) assert(skillEntries.includes(skill.name));

console.log("readonly skill tests passed");
