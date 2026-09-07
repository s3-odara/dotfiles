import { fileURLToPath } from "node:url";

// Fixed, user-owned roles. These are not Pi skills or project-discovered agents.
export const AGENTS = {
  explorer: {
    artifactDir: "research", workspaceLock: false,
    provider: "openai-codex", model: "gpt-5.6-luna", thinking: "low",
  },
  implementer: {
    artifactDir: "impl-reports", workspaceLock: true,
    provider: "openai-codex", model: "gpt-5.6-sol", thinking: "medium",
  },
  "internet-researcher": {
    artifactDir: "research", workspaceLock: false,
    provider: "openai-codex", model: "gpt-5.6-terra", thinking: "medium",
  },
  reviewer: {
    artifactDir: "reviews", workspaceLock: false,
    provider: "openai-codex", model: "gpt-5.6-luna", thinking: "medium",
  },
} as const;

export type AgentName = keyof typeof AGENTS;
export const agentNames = Object.keys(AGENTS) as AgentName[];
export const startPanePath = fileURLToPath(new URL("./scripts/start-bg-pane.sh", import.meta.url));
export const waitPath = fileURLToPath(new URL("./scripts/wait-for-children.sh", import.meta.url));
export function promptPath(agent: AgentName): string {
  return fileURLToPath(new URL(`../../agents/${agent}.md`, import.meta.url));
}

export function isChild(): boolean {
  // Also refuse launches from an old child still running during migration.
  return Boolean(process.env.PI_AGENT_CHILD || process.env.PI_CHILD_RUNNER_SKILL);
}
