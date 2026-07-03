import { existsSync, realpathSync } from "node:fs";
import { isAbsolute, join, resolve } from "node:path";

export const TMUX_MANAGED_SKILLS = [
  "explorer",
  "internet-researcher",
  "code-reviewer",
  "debugger",
  "tester",
  "plan-reviewer",
  "implementer",
  "review-orchestrator",
];

export interface Skill {
  name: string;
  launcherPath: string;
  promptPath: string;
  waitForChildrenPath: string;
}

export function findSkills(): Skill[] {
  const base = resolve(
    process.env.PI_CODING_AGENT_DIR ??
    join(process.env.HOME ?? "/home/user", ".config", "pi", "agent"),
    "skills",
  );
  const launcherPath = normalizePath(join(base, "scripts", "run-skill-background.sh"));
  const waitForChildrenPath = normalizePath(join(base, "scripts", "wait-for-children.sh"));
  if (!existsSync(launcherPath)) return [];

  return TMUX_MANAGED_SKILLS
    .filter((name) => existsSync(join(base, name, "SKILL.md")))
    .map((name) => ({
      name,
      launcherPath,
      promptPath: normalizePath(join(base, name, "SKILL.md")),
      waitForChildrenPath,
    }));
}

export function normalizePath(path: string, cwd = process.cwd()): string {
  const absolutePath = isAbsolute(path) ? path : resolve(cwd, path);
  return existsSync(absolutePath) ? realpathSync(absolutePath) : resolve(absolutePath);
}

export function parseLauncherOutput(stdout: string): Record<string, string> {
  const values: Record<string, string> = {};
  for (const line of stdout.split(/\r?\n/)) {
    const match = line.match(/^([A-Z0-9_]+)='([^']*)'$/);
    if (match) values[match[1]] = match[2];
  }
  return values;
}

export function snippet(value: string): string | undefined {
  if (!value) return undefined;
  return value.length > 4000 ? `${value.slice(0, 4000)}…` : value;
}
