import { existsSync } from "node:fs";
import { join } from "node:path";

const TMUX_MANAGED_SKILLS = [
  "explorer",
  "internet-researcher",
  "code-reviewer",
  "debugger",
  "tester",
  "plan-reviewer",
  "implementer",
  "review-orchestrator",
];

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
  launcherPath: string;
}

function buildSpawnInstruction(skill: Skill, task: string, cwd: string): string {
  return [
    "Run this explicit skill request by starting an interactive Pi pane in the shared tmux `agent` window. Use bash to execute the command block exactly. The launcher waits for the child to finish; while it is waiting, the child can be viewed or steered in the `agent` tmux window. When it completes, print the artifact path returned by the launcher.",
    "",
    "```bash",
    "set -euo pipefail",
    `launch_output=$(${shellQuote(skill.launcherPath)} --skill ${shellQuote(skill.name)} --task ${shellQuote(task)} --cwd ${shellQuote(cwd)})`,
    "printf '%s\\n' \"$launch_output\"",
    "printf '\\nChild ran interactively in tmux window `agent` and finished.\\n'",
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
  const launcherPath = join(base, "scripts", "run-skill-background.sh");
  if (!existsSync(launcherPath)) return [];

  return TMUX_MANAGED_SKILLS
    .filter((name) => existsSync(join(base, name, "SKILL.md")))
    .map((name) => ({ name, launcherPath }));
}
