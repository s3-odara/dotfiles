import { existsSync, realpathSync } from "node:fs";
import { isAbsolute, join, resolve } from "node:path";

export type ArtifactDir = "research" | "plans" | "specs" | "reviews" | "impl-reports";

const SKILL_CONFIG = {
  explorer: { artifactDir: "research", workspaceLock: false },
  "internet-researcher": { artifactDir: "research", workspaceLock: false },
  "code-reviewer": { artifactDir: "reviews", workspaceLock: false },
  "plan-reviewer": { artifactDir: "reviews", workspaceLock: false },
  implementer: { artifactDir: "impl-reports", workspaceLock: true },
  "review-orchestrator": { artifactDir: "reviews", workspaceLock: false },
} as const satisfies Record<string, { artifactDir: ArtifactDir; workspaceLock: boolean }>;

export const TMUX_MANAGED_SKILLS = Object.keys(SKILL_CONFIG);

export interface Skill {
  name: string;
  startPanePath: string;
  promptPath: string;
  waitForChildrenPath: string;
  artifactDir: ArtifactDir;
  workspaceLock: boolean;
}

export function findSkills(): Skill[] {
  const base = resolve(
    process.env.PI_CODING_AGENT_DIR ??
    join(process.env.HOME ?? "/home/user", ".config", "pi", "agent"),
    "skills",
  );
  const startPanePath = normalizePath(join(base, "scripts", "start-bg-pane.sh"));
  const waitForChildrenPath = normalizePath(join(base, "scripts", "wait-for-children.sh"));
  if (!existsSync(startPanePath) || !existsSync(waitForChildrenPath)) return [];

  return Object.entries(SKILL_CONFIG)
    .filter(([name]) => existsSync(join(base, name, "SKILL.md")))
    .map(([name, config]) => ({
      name,
      startPanePath,
      promptPath: normalizePath(join(base, name, "SKILL.md")),
      waitForChildrenPath,
      artifactDir: config.artifactDir,
      workspaceLock: config.workspaceLock,
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
