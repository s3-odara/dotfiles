import { modelArgsForSkill } from "./model-config.ts";
import { findSkills, type Skill } from "./skills.ts";

export default function registerSkillTmuxManualRunner(pi: any) {
  const skills = findSkills();
  const skillByName = new Map(skills.map((skill) => [skill.name, skill]));

  // User input only: rewrite explicit /skill:name prompts before Pi expands
  // them into SKILL.md content. Automatic model skill loading is handled by
  // auto.ts through read redirects and the run_skill tool.
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

function buildSpawnInstruction(skill: Skill, task: string, cwd: string): string {
  return [
    "Run this explicit skill request by starting an interactive Pi pane in the shared tmux `agent` window. Use bash to execute the command block exactly. The launcher waits for the child to finish; while it is waiting, the child can be viewed or steered in the `agent` tmux window. When it completes, print the artifact path returned by the launcher.",
    "",
    "```bash",
    "set -euo pipefail",
    `launch_output=$(${shellQuote(skill.launcherPath)} ${shellArgs(["--skill", skill.name, "--task", task, "--cwd", cwd, ...modelArgsForSkill(skill.name)])})`,
    "printf '%s\\n' \"$launch_output\"",
    "printf '\\nChild ran interactively in tmux window `agent` and finished.\\n'",
    "```",
  ].join("\n");
}

function shellArgs(values: string[]): string {
  return values.map(shellQuote).join(" ");
}

function shellQuote(value: string): string {
  return `'${value.replaceAll("'", `'\\''`)}'`;
}
