import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";

export default function (pi: any) {
  const skills = findSkills();
  const skillByName = new Map(skills.map((skill) => [skill.name, skill]));

  // User input only: rewrite explicit /skill:name prompts before Pi expands
  // them into SKILL.md content. Automatic model skill loading is intentionally
  // not intercepted here.
  pi.on?.("input", async (event: any, ctx: any) => {
    if (event?.source === "extension") return { action: "continue" };

    const text: string = event?.text ?? "";
    if (!text.startsWith("/skill:")) return { action: "continue" };

    const match = text.match(/^\/skill:([^\s]+)(?:\s+([\s\S]*))?$/);
    if (!match) return { action: "continue" };

    const skill = skillByName.get(match[1]);
    if (!skill) return { action: "continue" };

    const task = match[2]?.trim() || `Run ${skill.name} skill`;
    ctx?.ui?.notify?.(`🚀 ${skill.name} → tmux child`, "info");
    return {
      action: "transform",
      text: buildSpawnInstruction(skill, task, ctx?.cwd ?? process.cwd()),
    };
  });
}

interface Skill {
  name: string;
  mode: string;
  launcherPath: string;
}

function buildSpawnInstruction(skill: Skill, task: string, cwd: string): string {
  if (skill.mode === "coordinator") return buildCoordinatorInstruction(skill, task, cwd);

  const waitScript = join(dirname(skill.launcherPath), "wait-for-children.sh");
  return [
    "Run this explicit skill request in a tmux child. Use bash to execute the command block exactly, wait for completion, then read and summarize the artifact path printed at the end.",
    "",
    "```bash",
    "set -euo pipefail",
    `status_json=$(${shellQuote(skill.launcherPath)} --skill ${shellQuote(skill.name)} --task ${shellQuote(task)} --cwd ${shellQuote(cwd)})`,
    "run_id=${status_json##*/}",
    "run_id=${run_id%.json}",
    `${shellQuote(waitScript)} --agents-dir ${shellQuote(join(cwd, ".agents"))} --run-id "$run_id" --timeout 600 --poll 1`,
    "node -e 'const fs=require(\"fs\"); const s=JSON.parse(fs.readFileSync(process.argv[1],\"utf8\")); console.log(s.artifact_path);' \"$status_json\"",
    "```",
  ].join("\n");
}

function buildCoordinatorInstruction(skill: Skill, task: string, cwd: string): string {
  return [
    "Run this explicit coordinator skill request. Use bash to execute the command block exactly, then read and summarize the artifact path printed at the end.",
    "",
    "```bash",
    "set -euo pipefail",
    `artifact_path=$(${shellQuote(skill.launcherPath)} --skill ${shellQuote(skill.name)} --task ${shellQuote(task)} --cwd ${shellQuote(cwd)})`,
    "printf '%s\n' \"$artifact_path\"",
    "```",
  ].join("\n");
}

function shellQuote(value: string): string {
  return `'${value.replaceAll("'", `'\\''`)}'`;
}

function findSkills(): Skill[] {
  const base = join(
    process.env.PI_CODING_AGENT_DIR ??
    join(process.env.HOME ?? "/home/user", ".config", "pi", "agent"),
    "skills",
  );
  const launcherPath = join(base, "scripts", "spawn-skill-tmux-child.sh");
  const manifestPath = join(base, "scripts", "tmux-managed-skills.tsv");
  if (!existsSync(launcherPath) || !existsSync(manifestPath)) return [];

  const result: Skill[] = [];
  for (const line of readFileSync(manifestPath, "utf8").split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const [name, , mode] = line.split("\t");
    if (name && mode && existsSync(join(base, name, "SKILL.md"))) result.push({ name, mode, launcherPath });
  }
  return result;
}
