import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, readdir, stat, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawn, spawnSync } from "node:child_process";

const root = new URL("..", import.meta.url).pathname;

const skills = [
  { name: "explorer", artifactDir: "research", readonly: true },
  { name: "internet-researcher", artifactDir: "research", readonly: true },
  { name: "tester", artifactDir: "reviews", readonly: false },
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
if [[ "$1" != "new-session" || "$2" != "-d" || "$3" != "-s" ]]; then
  printf 'unsupported fake tmux invocation: %s\\n' "$*" >&2
  exit 9
fi
session="$4"
command="$5"
printf '%s\\n' "$session" >>"${dir}/sessions.log"
bash "$command" || true
`, { mode: 0o755 });
  await writeFile(join(bin, "pi"), `#!/usr/bin/env bash
set -euo pipefail
case "${'${PI_FAKE_MODE:-success}'}" in
  success)
    printf '# %s artifact\\n\\nTask file: %s\\n' "$PI_CHILD_RUNNER_SKILL" "$PI_CHILD_RUNNER_TASK_FILE" >"$PI_CHILD_RUNNER_ARTIFACT_PATH"
    ;;
  mcp-unavailable)
    # This fixture models the internet-researcher prompt's required behavior
    # when web MCP tools are absent. It still writes the requested artifact so
    # the shared helper success path remains covered separately from the
    # generic missing-artifact failure path.
    printf '# MCP Web Tools Unavailable\\n\\nConfigured web MCP tools were not available; research is limited.\\n' >"$PI_CHILD_RUNNER_ARTIFACT_PATH"
    ;;
  missing-artifact)
    :
    ;;
esac
`, { mode: 0o755 });
  return { dir, bin, cwd };
}

function statusPathFromStdout(stdout: string): string {
  const statusPath = stdout.trim().split(/\n/).find((line) => line.endsWith(".json"));
  assert(statusPath, "wrapper stdout should include a status JSON path");
  return statusPath;
}

function wrapperPath(skill: string) {
  return join(root, "skills", "scripts", "spawn-skill-tmux-child.sh");
}

function slug(value: string) {
  return value.replaceAll("_", "-");
}

async function runWrapper(fixture: SkillFixture, skill: Skill, extraEnv: Record<string, string> = {}) {
  const result = spawnSync(wrapperPath(skill.name), [
    "--skill", skill.name,
    "--task", `Check ${skill.name}`,
    "--cwd", fixture.cwd,
    "--timeout", "1",
  ], {
    cwd: root,
    env: { ...process.env, PATH: `${fixture.bin}:${process.env.PATH}`, ...extraEnv },
    encoding: "utf8",
  });
  assert.equal(result.status, 0, result.stderr);
  const status = JSON.parse(await readFile(statusPathFromStdout(result.stdout), "utf8"));
  assert.equal(status.skill, skill.name);
  assert.equal(status.status, "success");
  assert.match(status.session_name, new RegExp(`^pi-${skill.name}-check-${slug(skill.name)}-\\d{14}-\\d+-[a-f0-9]+$`));
  assert.match(status.artifact_path, new RegExp(`\\.agents/${skill.artifactDir}/pi-${skill.name}-check-${slug(skill.name)}-\\d{14}-\\d+-[a-f0-9]+\\.md$`));
  await stat(status.success_sentinel_path);
  assert.match(await readFile(status.artifact_path, "utf8"), new RegExp(`# ${skill.name} artifact`));
  assert.equal(await readFile(join(fixture.cwd, "source.txt"), "utf8"), "unchanged\n");
  return status;
}

async function testSkillMetadataAndWrappers() {
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

async function testWrappersProduceCanonicalArtifacts() {
  const fixture = await makeFixture();
  for (const skill of skills) await runWrapper(fixture, skill);
  const sessions = (await readFile(join(fixture.dir, "sessions.log"), "utf8")).trim().split(/\n/);
  assert.equal(new Set(sessions).size, skills.length);
}

async function testConcurrentReadonlyWrappersDoNotCollide() {
  const fixture = await makeFixture();
  const selected = skills.filter((skill) => skill.readonly).slice(0, 2);
  const run = (skill) => new Promise((resolve, reject) => {
    const child = spawn(wrapperPath(skill.name), [
      "--skill", skill.name,
      "--task", "Concurrent read check",
      "--cwd", fixture.cwd,
      "--timeout", "1",
    ], { env: { ...process.env, PATH: `${fixture.bin}:${process.env.PATH}` } });
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
  const result = spawnSync(wrapperPath("internet-researcher"), [
    "--skill", "internet-researcher",
    "--task", "Research with unavailable MCP tools",
    "--cwd", fixture.cwd,
    "--timeout", "1",
  ], {
    cwd: root,
    env: { ...process.env, PATH: `${fixture.bin}:${process.env.PATH}`, PI_FAKE_MODE: "missing-artifact" },
    encoding: "utf8",
  });
  assert.equal(result.status, 0, result.stderr);
  const status = JSON.parse(await readFile(statusPathFromStdout(result.stdout), "utf8"));
  assert.equal(status.status, "failure");
  assert.equal(status.failure_reason, "missing-artifact");
  assert.match(await readFile(status.artifact_path, "utf8"), /Child Run Failure/);
}

async function testInternetResearcherUnavailableMcpWritesLimitationArtifact() {
  const fixture = await makeFixture();
  const result = spawnSync(wrapperPath("internet-researcher"), [
    "--skill", "internet-researcher",
    "--task", "Research with unavailable MCP tools",
    "--cwd", fixture.cwd,
    "--timeout", "1",
  ], {
    cwd: root,
    env: { ...process.env, PATH: `${fixture.bin}:${process.env.PATH}`, PI_FAKE_MODE: "mcp-unavailable" },
    encoding: "utf8",
  });
  assert.equal(result.status, 0, result.stderr);
  const status = JSON.parse(await readFile(statusPathFromStdout(result.stdout), "utf8"));
  assert.equal(status.skill, "internet-researcher");
  assert.equal(status.status, "success");
  assert.match(await readFile(status.artifact_path, "utf8"), /MCP Web Tools Unavailable/);
}

await testSkillMetadataAndWrappers();
await testWrappersProduceCanonicalArtifacts();
await testConcurrentReadonlyWrappersDoNotCollide();
await testInternetResearcherUnavailableMcpWritesFailureArtifact();
await testInternetResearcherUnavailableMcpWritesLimitationArtifact();

const skillEntries = await readdir(join(root, "skills"));
for (const skill of skills) assert(skillEntries.includes(skill.name));

console.log("readonly skill tests passed");
