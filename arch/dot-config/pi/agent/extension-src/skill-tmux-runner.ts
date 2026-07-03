import { existsSync, realpathSync } from "node:fs";
import { isAbsolute, join, resolve } from "node:path";

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
  const skillByPromptPath = new Map(skills.map((skill) => [skill.promptPath, skill]));

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

  pi.on?.("tool_result", async (event: any, ctx: any) => {
    if (event?.toolName !== "read") return undefined;

    const readPath = event?.input?.path;
    if (typeof readPath !== "string" || readPath.length === 0) {
      return undefined;
    }

    const skill = skillByPromptPath.get(normalizePath(readPath, ctx?.cwd ?? process.cwd()));
    if (!skill) return undefined;

    return {
      content: [
        {
          type: "text",
          text: `${skill.name} is tmux-managed. Do not execute this SKILL.md inline. Call the run_skill tool with skill: "${skill.name}", a concrete task, and the current cwd; then use the returned artifact/status.`,
        },
      ],
      details: { status: "redirected", skill: skill.name, promptPath: skill.promptPath },
      isError: false,
    };
  });

  if (typeof pi?.registerTool === "function") {
    pi.registerTool({
      name: "run_skill",
      label: "Run Skill",
      description: "Run a tmux-managed bundled Pi skill through the central tmux launcher and return its artifact path.",
      promptSnippet: "Use run_skill for tmux-managed bundled skills instead of reading their SKILL.md prompts inline.",
      promptGuidelines: [
        "Use only for discovered tmux-managed skills.",
        "Provide a concrete task and then read/use the returned artifact path.",
      ],
      parameters: {
        type: "object",
        additionalProperties: false,
        required: ["skill", "task"],
        properties: {
          skill: { type: "string", enum: skills.map((skill) => skill.name) },
          task: { type: "string", minLength: 1 },
          cwd: { type: "string" },
        },
      },
      async execute(_toolCallId: string, params: any, signal?: AbortSignal, _onUpdate?: unknown, ctx?: any) {
        return runSkillTool(pi, skillByName, params, ctx, signal);
      },
    });
  }
}

interface Skill {
  name: string;
  launcherPath: string;
  promptPath: string;
}

interface ToolResultDetails {
  status: "success" | "failed";
  skill?: string;
  cwd?: string;
  artifactPath?: string;
  code?: number;
  killed?: boolean;
  stdout?: string;
  stderr?: string;
  error?: string;
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
  const base = resolve(
    process.env.PI_CODING_AGENT_DIR ??
    join(process.env.HOME ?? "/home/user", ".config", "pi", "agent"),
    "skills",
  );
  const launcherPath = normalizePath(join(base, "scripts", "run-skill-background.sh"));
  if (!existsSync(launcherPath)) return [];

  return TMUX_MANAGED_SKILLS
    .filter((name) => existsSync(join(base, name, "SKILL.md")))
    .map((name) => ({
      name,
      launcherPath,
      promptPath: normalizePath(join(base, name, "SKILL.md")),
    }));
}

function normalizePath(path: string, cwd = process.cwd()): string {
  const absolutePath = isAbsolute(path) ? path : resolve(cwd, path);
  return existsSync(absolutePath) ? realpathSync(absolutePath) : resolve(absolutePath);
}

async function runSkillTool(pi: any, skillByName: Map<string, Skill>, params: any, ctx: any, signal?: AbortSignal) {
  const skillName = typeof params?.skill === "string" ? params.skill : "";
  const task = typeof params?.task === "string" ? params.task.trim() : "";
  const skill = skillByName.get(skillName);
  const cwd = typeof params?.cwd === "string" && params.cwd.length > 0
    ? params.cwd
    : (ctx?.cwd ?? process.cwd());

  if (!skill || task.length === 0) {
    const details: ToolResultDetails = {
      status: "failed",
      skill: skillName || undefined,
      cwd,
      error: !skill ? `Invalid tmux-managed skill: ${skillName}` : "Task must be a non-empty string",
    };
    return failedToolResult(details);
  }

  const args = ["--skill", skill.name, "--task", task, "--cwd", cwd];
  try {
    if (typeof pi?.exec !== "function") {
      return failedToolResult({ status: "failed", skill: skill.name, cwd, error: "Pi exec API is unavailable" });
    }
    // Pi exposes process execution on the extension API, not the per-call ctx.
    // Keep argv separated so task/cwd text is passed verbatim instead of being
    // shell-parsed; the explicit /skill input hook remains a bash snippet only
    // because that path must be visible and copyable for an interactive user.
    const result = await pi.exec(skill.launcherPath, args, { signal });
    const stdout = String(result?.stdout ?? "");
    const stderr = String(result?.stderr ?? "");
    const code = typeof result?.code === "number" ? result.code : undefined;
    const killed = result?.killed === true;
    const artifactPath = parseArtifactPath(stdout);

    if (killed || (typeof code === "number" && code !== 0)) {
      return failedToolResult({ status: "failed", skill: skill.name, cwd, code, killed, stdout: snippet(stdout), stderr: snippet(stderr) });
    }
    if (!artifactPath) {
      return failedToolResult({ status: "failed", skill: skill.name, cwd, code, killed, stdout: snippet(stdout), stderr: snippet(stderr), error: "Launcher output did not include a trusted ARTIFACT_PATH='...' line" });
    }

    return {
      content: [{ type: "text", text: `${skill.name} tmux child completed. Use the returned artifactPath as the primary artifact to read/use: ${artifactPath}` }],
      details: { status: "success", skill: skill.name, cwd, artifactPath },
    };
  } catch (error) {
    return failedToolResult({ status: "failed", skill: skill.name, cwd, error: error instanceof Error ? error.message : String(error) });
  }
}

function parseArtifactPath(stdout: string): string | undefined {
  // Parse only the launcher's trusted single-quoted assignment line; do not eval
  // arbitrary child output that may appear alongside it.
  return stdout.split(/\r?\n/).map((line) => line.match(/^ARTIFACT_PATH='([^']+)'$/)?.[1]).find(Boolean);
}

function failedToolResult(details: ToolResultDetails) {
  return {
    content: [{ type: "text", text: `run_skill failed: ${details.error ?? "launcher did not complete successfully"}` }],
    details,
    isError: true,
  };
}

function snippet(value: string): string | undefined {
  if (!value) return undefined;
  return value.length > 4000 ? `${value.slice(0, 4000)}…` : value;
}
