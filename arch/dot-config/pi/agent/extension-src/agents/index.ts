import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import type { ExtensionAPI } from "../types.ts";
import { AGENTS, agentNames, isChild, promptPath, startPanePath, waitPath, type AgentName } from "./config.ts";

interface Assignment {
  agent: AgentName;
  task: string;
  context: string;
  constraints: string;
  expected_output: string;
}
interface RunContext {
  cwd: string;
}
const requiredText = ["task", "context", "constraints", "expected_output"] as const;

export default function registerAgents(pi: ExtensionAPI): void {
  if (isChild()) return;
  pi.registerTool?.({
    name: "run_agent",
    label: "Run Agent",
    description: "Delegate one self-contained assignment to an independent subagent in tmux and wait for its report. Only the main agent can call this. Roles: explorer (local lookup and concise evidence-backed answers, no evaluation), implementer (edit and test), internet-researcher (external research), reviewer (review only). Children cannot delegate and do not receive your conversation or tool history. Returns a report path; read it before deciding what to do next.",
    promptSnippet: "Delegate a self-contained assignment to an independent subagent and wait for its report",
    promptGuidelines: [
      "You are the main agent. Own design discussions and write any plans/specifications yourself. Use run_agent only when delegation is useful; handle small tasks directly. Do not require documents or a planning/implementation/review pipeline for every task.",
      "Use run_agent explorer for scoped local lookup, not design evaluation or recommendations. Its lower-capability model returns navigation hints and provisional factual answers, not authoritative conclusions. Read the cited source before consequential judgments; do not treat its recommendations or a not-found report as evidence of quality, correctness or absence.",
      "Before run_agent implementation, distinguish agreed decisions from proposals and open questions in the handoff. Surface consequential unagreed design choices to the user before implementation; a written plan is not itself approval.",
      "For run_agent, write a complete handoff: task, relevant facts and decisions, file/report paths and summaries, commands/results/errors, constraints and non-goals, and expected output. No conversation or tool history is inherited. State what is unknown rather than implying shared context.",
      "Read every run_agent report. Resolve missing information, approvals, findings and follow-up work yourself; only the main agent orchestrates. Do not edit a workspace while its implementer is running.",
      "Skills are inline knowledge and procedures, not subagents. Use run_agent directly for delegation; do not read agent role files or launch child Pi processes through bash.",
    ],
    parameters: {
      type: "object", additionalProperties: false,
      required: ["agent", ...requiredText],
      properties: {
        agent: { type: "string", enum: agentNames },
        task: { type: "string", minLength: 1, description: "Concrete objective and scope of this assignment." },
        context: { type: "string", minLength: 1, description: "Relevant facts, decisions, file/artifact paths with summaries, prior commands/results/errors, and known unknowns. If nothing has been investigated, say so explicitly." },
        constraints: { type: "string", minLength: 1, description: "Allowed changes, non-goals, prohibitions, approval boundaries and user requirements." },
        expected_output: { type: "string", minLength: 1, description: "Deliverables, acceptance criteria and validation to report; specify the review target/base when reviewing." },
      },
    },
    async execute(_id: string, assignment: Assignment, signal: AbortSignal | undefined, _onUpdate: unknown, ctx: RunContext) {
      // Check again at execution, not only registration. The shell launcher also checks.
      if (isChild()) throw new Error("Subagents cannot delegate. Return missing context or blocked work to the main agent.");
      if (!assignment || !agentNames.includes(assignment.agent)) throw new Error("Invalid subagent role");
      for (const key of requiredText) {
        if (typeof assignment[key] !== "string" || !assignment[key].trim()) {
          throw new Error(`run_agent requires a non-empty ${key}; provide a self-contained handoff`);
        }
      }
      if (typeof pi.exec !== "function") throw new Error("Pi exec API is unavailable");
      if (signal?.aborted) throw new Error("run_agent cancelled before launch");

      const agent = assignment.agent;
      const config = AGENTS[agent];
      const cwd = resolve(ctx.cwd);
      const brief = [
        "## Task", assignment.task.trim(),
        "## Context", assignment.context.trim(),
        "## Constraints", assignment.constraints.trim(),
        "## Expected output", assignment.expected_output.trim(),
      ].join("\n\n");
      const args = [
        "--agent", agent, "--artifact-dir", config.artifactDir,
        "--role-prompt", promptPath(agent), "--task", brief, "--cwd", cwd,
      ];
      args.push("--provider", config.provider, "--model", config.model, "--thinking", config.thinking);
      if (config.workspaceLock) args.push("--workspace-lock");

      const launch = await pi.exec(startPanePath, args, { signal });
      if (launch.killed || launch.code !== 0) {
        throw new Error(`Subagent launch failed: ${snippet(launch.stderr || launch.stdout || "launcher terminated")}`);
      }
      const paths = parseLauncherOutput(String(launch.stdout));
      const artifactPath = paths.ARTIFACT_PATH;
      if (!artifactPath || !paths.SUCCESS_SENTINEL || !paths.FAILURE_SENTINEL) {
        throw new Error("Subagent launcher did not return artifact and sentinel paths");
      }
      const wait = await pi.exec(waitPath, [
        "--success", paths.SUCCESS_SENTINEL, "--failure", paths.FAILURE_SENTINEL,
        "--timeout", "1800", "--poll", "1",
      ], { signal });
      if (wait.killed || wait.code !== 0) {
        let reason = String(wait.stderr || wait.stdout || "wait cancelled");
        try { reason = readFileSync(`${paths.FAILURE_SENTINEL}.reason`, "utf8").trim(); } catch { /* no failure sentinel on timeout/cancel */ }
        throw new Error(`Subagent did not complete: ${snippet(reason)}. Report (may be missing): ${artifactPath}. The tmux pane may still be running; inspect it before retrying or editing this workspace.`);
      }
      return {
        content: [{ type: "text", text: `${agent} completed. Read the report before continuing: ${artifactPath}` }],
        details: { agent, cwd, artifactPath },
      };
    },
  });
}

// Launcher emits shell-quoted values, including paths containing apostrophes.
// Parse just this tiny contract; never evaluate shell output.
export function parseLauncherOutput(stdout: string): Record<string, string> {
  const values: Record<string, string> = {};
  for (const line of stdout.split(/\r?\n/)) {
    const match = line.match(/^(ARTIFACT_PATH|SUCCESS_SENTINEL|FAILURE_SENTINEL)='((?:[^']|'\\'')*)'$/);
    if (match) values[match[1]] = match[2].replaceAll("'\\''", "'");
  }
  return values;
}
function snippet(value: string): string {
  return String(value).slice(0, 4000);
}
