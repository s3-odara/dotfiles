export type ThinkingLevel = "off" | "minimal" | "low" | "medium" | "high" | "xhigh";

export interface SkillModelConfig {
  provider?: string;
  model?: string;
  thinking?: ThinkingLevel;
}

export const SKILL_MODEL_CONFIG: Record<string, SkillModelConfig> = {
  explorer: {
    provider: "openai-codex",
    model: "gpt-5.4-mini",
    thinking: "low",
  },
  "code-reviewer": {
    provider: "openai-codex",
    model: "gpt-5.4-mini",
    thinking: "medium",
  },
  debugger: {
    provider: "openai-codex",
    model: "gpt-5.5",
    thinking: "high",
  },
  implementer: {
    provider: "openai-codex",
    model: "gpt-5.5",
    thinking: "medium",
  },
  "review-orchestrator": {
    provider: "openai-codex",
    model: "gpt-5.5",
    thinking: "high",
  },
};

export function modelArgsForSkill(skillName: string): string[] {
  const config = SKILL_MODEL_CONFIG[skillName];
  if (!config) return [];

  const args: string[] = [];
  if (config.provider) args.push("--provider", config.provider);
  if (config.model) args.push("--model", config.model);
  if (config.thinking) args.push("--thinking", config.thinking);
  return args;
}
