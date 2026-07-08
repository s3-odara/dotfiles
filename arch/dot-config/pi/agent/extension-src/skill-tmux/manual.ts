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
      text: buildRunSkillInstruction(skill, task, ctx?.cwd ?? process.cwd()),
    };
  });
}

function buildRunSkillInstruction(skill: Skill, task: string, cwd: string): string {
  return [
    "Run this explicit skill request with the `run_skill` tool. Do not read or execute the SKILL.md inline.",
    "",
    "Tool arguments:",
    `- skill: ${skill.name}`,
    `- task: ${task}`,
    `- cwd: ${cwd}`,
    "",
    "After the tool completes, read/use the returned artifactPath as the primary result.",
  ].join("\n");
}
