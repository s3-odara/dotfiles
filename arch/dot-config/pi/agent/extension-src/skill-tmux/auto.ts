import { existsSync } from "node:fs";
import { modelArgsForSkill } from "./model-config.ts";
import { findSkills, normalizePath, parseLauncherOutput, snippet, type Skill } from "./skills.ts";

interface ToolResultDetails {
  status: "success" | "failed" | "started";
  skill?: string;
  cwd?: string;
  artifactPath?: string;
  successSentinel?: string;
  failureSentinel?: string;
  code?: number;
  killed?: boolean;
  stdout?: string;
  stderr?: string;
  error?: string;
}

interface StartedRun {
  skill: string;
  cwd: string;
  artifactPath: string;
  successSentinel: string;
  failureSentinel: string;
  waitForChildrenPath: string;
}

export default function registerSkillTmuxAutoRunner(pi: any) {
  const skills = findSkills();
  const skillByName = new Map(skills.map((skill) => [skill.name, skill]));
  const skillByPromptPath = new Map(skills.map((skill) => [skill.promptPath, skill]));

  pi.on?.("tool_result", async (event: any, ctx: any) => {
    if (event?.toolName !== "read") return undefined;

    const readPath = event?.input?.path;
    if (typeof readPath !== "string" || readPath.length === 0) return undefined;

    const skill = skillByPromptPath.get(normalizePath(readPath, ctx?.cwd ?? process.cwd()));
    if (!skill) return undefined;

    return {
      content: [
        {
          type: "text",
          text: `${skill.name} is tmux-managed. Do not execute this SKILL.md inline. Call the run_skill tool with skill: "${skill.name}", a concrete task, and the current cwd; then use the returned artifact/status. If the immediate next step does not need the child artifact, set noWait=true so the child can run asynchronously; otherwise omit noWait and wait for completion.`,
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
        "Set noWait=true when you want to start the tmux child and continue; this requires follow-up message support and Pi will notify you when it finishes.",
      ],
      parameters: {
        type: "object",
        additionalProperties: false,
        required: ["skill", "task"],
        properties: {
          skill: { type: "string", enum: skills.map((skill) => skill.name) },
          task: { type: "string", minLength: 1 },
          cwd: { type: "string" },
          noWait: { type: "boolean" },
        },
      },
      async execute(_toolCallId: string, params: any, signal?: AbortSignal, _onUpdate?: unknown, ctx?: any) {
        return runSkillTool(pi, skillByName, params, ctx, signal);
      },
    });
  }
}

async function runSkillTool(pi: any, skillByName: Map<string, Skill>, params: any, ctx: any, signal?: AbortSignal) {
  const skillName = typeof params?.skill === "string" ? params.skill : "";
  const task = typeof params?.task === "string" ? params.task.trim() : "";
  const noWait = params?.noWait === true;
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

  const args = ["--skill", skill.name, "--task", task, "--cwd", cwd, ...modelArgsForSkill(skill.name)];
  if (noWait) args.push("--no-wait");

  try {
    if (typeof pi?.exec !== "function") {
      return failedToolResult({ status: "failed", skill: skill.name, cwd, error: "Pi exec API is unavailable" });
    }
    if (noWait && typeof pi?.sendUserMessage !== "function") {
      return failedToolResult({ status: "failed", skill: skill.name, cwd, error: "noWait requires Pi follow-up message support" });
    }
    if (noWait && !existsSync(skill.waitForChildrenPath)) {
      return failedToolResult({ status: "failed", skill: skill.name, cwd, error: "wait-for-children.sh is unavailable" });
    }

    const result = await pi.exec(skill.launcherPath, args, { signal });
    const stdout = String(result?.stdout ?? "");
    const stderr = String(result?.stderr ?? "");
    const code = typeof result?.code === "number" ? result.code : undefined;
    const killed = result?.killed === true;
    const launch = parseLauncherOutput(stdout);
    const artifactPath = launch.ARTIFACT_PATH;

    if (killed || (typeof code === "number" && code !== 0)) {
      return failedToolResult({ status: "failed", skill: skill.name, cwd, code, killed, stdout: snippet(stdout), stderr: snippet(stderr) });
    }
    if (!artifactPath) {
      return failedToolResult({ status: "failed", skill: skill.name, cwd, code, killed, stdout: snippet(stdout), stderr: snippet(stderr), error: "Launcher output did not include a trusted ARTIFACT_PATH='...' line" });
    }

    if (noWait) {
      const successSentinel = launch.SUCCESS_SENTINEL;
      const failureSentinel = launch.FAILURE_SENTINEL;
      if (!successSentinel || !failureSentinel) {
        return failedToolResult({ status: "failed", skill: skill.name, cwd, code, killed, stdout: snippet(stdout), stderr: snippet(stderr), error: "Launcher --no-wait output did not include sentinel paths" });
      }
      const run = { skill: skill.name, cwd, artifactPath, successSentinel, failureSentinel, waitForChildrenPath: skill.waitForChildrenPath };
      void watchStartedRun(pi, run, signal).catch((error) => {
        console.warn(`run_skill watcher failed for ${skill.name}:`, error);
      });
      return {
        content: [{ type: "text", text: `${skill.name} tmux child started. I will send a follow-up message when it finishes. Artifact path: ${artifactPath}` }],
        details: { status: "started", skill: skill.name, cwd, artifactPath, successSentinel, failureSentinel },
      };
    }

    return {
      content: [{ type: "text", text: `${skill.name} tmux child completed. Use the returned artifactPath as the primary artifact to read/use: ${artifactPath}` }],
      details: { status: "success", skill: skill.name, cwd, artifactPath },
    };
  } catch (error) {
    return failedToolResult({ status: "failed", skill: skill.name, cwd, error: error instanceof Error ? error.message : String(error) });
  }
}

async function watchStartedRun(pi: any, run: StartedRun, signal?: AbortSignal): Promise<void> {
  if (typeof pi?.exec !== "function") return;

  const result = await pi.exec(run.waitForChildrenPath, [
    "--success", run.successSentinel,
    "--failure", run.failureSentinel,
    "--timeout", "1800",
    "--poll", "1",
  ], { signal });
  const stdout = String(result?.stdout ?? "");
  const stderr = String(result?.stderr ?? "");
  const code = typeof result?.code === "number" ? result.code : undefined;
  const killed = result?.killed === true;
  const status = !killed && code === 0 ? "completed" : "failed";
  const text = [
    `run_skill ${status}: ${run.skill}`,
    `Artifact: ${run.artifactPath}`,
    `Working directory: ${run.cwd}`,
    status === "failed" ? `Diagnostics: ${snippet(stderr) ?? snippet(stdout) ?? "check the tmux pane and sentinels"}` : undefined,
  ].filter(Boolean).join("\n");

  if (signal?.aborted) return;

  if (typeof pi?.sendUserMessage === "function") {
    await pi.sendUserMessage(text, { deliverAs: "followUp" });
  } else {
    console.warn(text);
  }
}

function failedToolResult(details: ToolResultDetails) {
  return {
    content: [{ type: "text", text: `run_skill failed: ${details.error ?? "launcher did not complete successfully"}` }],
    details,
    isError: true,
  };
}
