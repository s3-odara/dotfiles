import assert from "node:assert/strict";
import { join } from "node:path";
import registerSkillTmuxAutoRunner from "../extension-src/skill-tmux/auto.ts";
import registerSkillTmuxManualRunner from "../extension-src/skill-tmux/manual.ts";

const root = new URL("..", import.meta.url).pathname;
const previousAgentDir = process.env.PI_CODING_AGENT_DIR;
process.env.PI_CODING_AGENT_DIR = root;

function makePi(options: { sendUserMessage?: boolean } = {}) {
  const handlers: Record<string, (...args: any[]) => unknown> = {};
  const tools: any[] = [];
  const userMessages: any[] = [];
  const pi: any = {
    on(eventName: string, handler: (...args: any[]) => unknown) {
      handlers[eventName] = handler;
    },
    registerTool(tool: any) {
      tools.push(tool);
    },
  };
  if (options.sendUserMessage !== false) {
    pi.sendUserMessage = (content: string, options?: any) => {
      userMessages.push({ content, options });
    };
  }
  return {
    handlers,
    tools,
    userMessages,
    pi,
  };
}

function registerBoth(pi: any) {
  registerSkillTmuxManualRunner(pi);
  registerSkillTmuxAutoRunner(pi);
}

const first = makePi();
registerBoth(first.pi);
assert.equal(typeof first.handlers.input, "function", "first runtime should register input hook");

const second = makePi();
registerBoth(second.pi);
assert.equal(typeof second.handlers.input, "function", "reload/rebind should register input hook again");
assert.equal(typeof second.handlers.tool_result, "function", "runtime should register tool_result hook");
assert.equal(second.tools.length, 1, "runtime should register exactly one tool");
assert.equal(second.tools[0].name, "run_skill");
assert(!second.tools[0].parameters.properties.skill.enum.includes("planner"));
assert(!second.tools[0].parameters.properties.skill.enum.includes("specifier"));
assert(second.tools[0].parameters.properties.skill.enum.includes("code-reviewer"));

const result = await second.handlers.input(
  { source: "interactive", text: "/skill:code-reviewer\nReview this diff\nwith details" },
  { cwd: root, ui: { notify() {} } },
);

assert.equal(result?.action, "transform");
assert.match(result.text, /run_skill/);
assert.match(result.text, /skill: code-reviewer/);
assert.match(result.text, /Review this diff\nwith details/);
assert.match(result.text, /returned artifactPath/);
assert.doesNotMatch(result.text, /run-skill-background\.sh|wait-for-children\.sh|node -e|JSON\.parse|status_json/);

const orchestratorResult = await second.handlers.input(
  { source: "interactive", text: "/skill:review-orchestrator Review this branch" },
  { cwd: root, ui: { notify() {} } },
);
assert.equal(orchestratorResult?.action, "transform");
assert.match(orchestratorResult.text, /run_skill/);
assert.match(orchestratorResult.text, /skill: review-orchestrator/);
assert.doesNotMatch(orchestratorResult.text, /run-skill-background\.sh|launch_output=|wait-for-children\.sh|artifact_path=\$\(/);

for (const [skill, task] of [["web-search", "Find sources"], ["planner", "Plan this"], ["specifier", "Specify this"]]) {
  const nativeSkillResult = await second.handlers.input(
    { source: "interactive", text: `/skill:${skill} ${task}` },
    { cwd: root, ui: { notify() {} } },
  );
  assert.equal(nativeSkillResult?.action, "continue", `${skill} should continue through Pi's native skill handling`);
}

const extensionResult = await second.handlers.input(
  { source: "extension", text: "/skill:code-reviewer Review this" },
  { cwd: root, ui: { notify() {} } },
);
assert.equal(extensionResult?.action, "continue");

const originalRoleContent = "ORIGINAL CODE REVIEWER ROLE CONTENT";
const redirectedRead = await second.handlers.tool_result(
  {
    toolName: "read",
    input: { path: join(root, "skills", "code-reviewer", "SKILL.md") },
    content: [{ type: "text", text: originalRoleContent }],
    details: {},
    isError: false,
  },
  { cwd: root },
);
assert.equal(redirectedRead?.isError, false);
assert.match(redirectedRead.content[0].text, /run_skill/);
assert.match(redirectedRead.content[0].text, /code-reviewer/);
assert.doesNotMatch(redirectedRead.content[0].text, new RegExp(originalRoleContent));

const webSearchRead = await second.handlers.tool_result(
  { toolName: "read", input: { path: join(root, "skills", "web-search", "SKILL.md") }, content: [], details: {}, isError: false },
  { cwd: root },
);
assert.equal(webSearchRead, undefined);

for (const skill of ["planner", "specifier"]) {
  const nativeSkillRead = await second.handlers.tool_result(
    { toolName: "read", input: { path: join(root, "skills", skill, "SKILL.md") }, content: [], details: {}, isError: false },
    { cwd: root },
  );
  assert.equal(nativeSkillRead, undefined, `${skill} SKILL.md reads should not be redirected`);
}

const arbitraryRead = await second.handlers.tool_result(
  { toolName: "read", input: { path: join(root, "package.json") }, content: [], details: {}, isError: false },
  { cwd: root },
);
assert.equal(arbitraryRead, undefined);

const nonRead = await second.handlers.tool_result(
  { toolName: "webfetch", input: { path: join(root, "skills", "code-reviewer", "SKILL.md") }, content: [], details: {}, isError: false },
  { cwd: root },
);
assert.equal(nonRead, undefined);

const execCalls: any[] = [];
const signal = new AbortController().signal;
(second.pi as any).exec = (command: string, args: string[], options: { signal?: AbortSignal }) => {
  execCalls.push({ command, args, options });
  if (command.endsWith("start-bg-pane.sh")) {
    return { stdout: "noise\nARTIFACT_PATH='/tmp/artifact.md'\nSUCCESS_SENTINEL='/tmp/artifact.success'\nFAILURE_SENTINEL='/tmp/artifact.failure'\n", stderr: "", code: 0, killed: false };
  }
  return { stdout: "OVERALL='success'\n", stderr: "", code: 0, killed: false };
};
const successToolResult = await second.tools[0].execute(
  "tool-call-1",
  { skill: "code-reviewer", task: "Review this diff", cwd: root },
  signal,
  undefined,
  { cwd: "/should/not/use" },
);
assert.equal(execCalls.length, 2);
assert.match(execCalls[0].command, /start-bg-pane\.sh$/);
assert.deepEqual(execCalls[0].args, [
  "--skill", "code-reviewer",
  "--artifact-dir", "reviews",
  "--prompt-template", join(root, "skills", "code-reviewer", "SKILL.md"),
  "--task", "Review this diff",
  "--cwd", root,
  "--timeout", "1800",
  "--provider", "openai-codex",
  "--model", "gpt-5.6-luna",
  "--thinking", "medium",
]);
assert.equal(execCalls[0].options.signal, signal);
assert.match(execCalls[1].command, /wait-for-children\.sh$/);
assert.deepEqual(execCalls[1].args, ["--success", "/tmp/artifact.success", "--failure", "/tmp/artifact.failure", "--timeout", "1800", "--poll", "1"]);
assert.equal(successToolResult.details.status, "success");
assert.equal(successToolResult.details.artifactPath, "/tmp/artifact.md");

const noWaitExecCalls: any[] = [];
const noWaitSignal = new AbortController().signal;
(second.pi as any).exec = (command: string, args: string[], options?: { signal?: AbortSignal }) => {
  noWaitExecCalls.push({ command, args, options });
  if (command.endsWith("start-bg-pane.sh")) {
    return {
      stdout: "ARTIFACT_PATH='/tmp/started.md'\nSUCCESS_SENTINEL='/tmp/started.success'\nFAILURE_SENTINEL='/tmp/started.failure'\n",
      stderr: "",
      code: 0,
      killed: false,
    };
  }
  return { stdout: "OVERALL='success'\n", stderr: "", code: 0, killed: false };
};
const noWaitToolResult = await second.tools[0].execute(
  "tool-call-no-wait",
  { skill: "code-reviewer", task: "Review async", cwd: root, noWait: true },
  noWaitSignal,
  undefined,
  { cwd: root },
);
assert.equal(noWaitToolResult.details.status, "started");
assert.equal(noWaitToolResult.details.artifactPath, "/tmp/started.md");
assert(!noWaitExecCalls[0].args.includes("--no-wait"));
assert.match(noWaitExecCalls[0].command, /start-bg-pane\.sh$/);
// Give the detached watcher promise a tick to run its fake wait helper and notification.
await new Promise((resolve) => setTimeout(resolve, 0));
assert.equal(noWaitExecCalls.length, 2);
assert.match(noWaitExecCalls[1].command, /wait-for-children\.sh$/);
assert.deepEqual(noWaitExecCalls[1].args, ["--success", "/tmp/started.success", "--failure", "/tmp/started.failure", "--timeout", "1800", "--poll", "1"]);
assert.equal(noWaitExecCalls[1].options.signal, noWaitSignal);
assert.equal(second.userMessages.length, 1);
assert.match(second.userMessages[0].content, /run_skill completed: code-reviewer/);
assert.match(second.userMessages[0].content, /Artifact: \/tmp\/started\.md/);
assert.deepEqual(second.userMessages[0].options, { deliverAs: "followUp" });

const noFollowUpRuntime = makePi({ sendUserMessage: false });
registerSkillTmuxAutoRunner(noFollowUpRuntime.pi);
(noFollowUpRuntime.pi as any).exec = () => { throw new Error("should not launch without follow-up support"); };
const noFollowUpResult = await noFollowUpRuntime.tools[0].execute(
  "tool-call-no-follow-up",
  { skill: "code-reviewer", task: "Review async", cwd: root, noWait: true },
  undefined,
  undefined,
  { cwd: root },
);
assert.equal(noFollowUpResult.isError, true);
assert.equal(noFollowUpResult.details.status, "failed");
assert.match(noFollowUpResult.details.error, /follow-up message support/);

const invalidSkillResult = await second.tools[0].execute(
  "tool-call-2",
  { skill: "web-search", task: "Search", cwd: root },
  undefined,
  undefined,
  { cwd: root },
);
assert.equal(invalidSkillResult.isError, true);
assert.equal(invalidSkillResult.details.status, "failed");
assert.match(invalidSkillResult.details.error, /Invalid tmux-managed skill/);

(second.pi as any).exec = () => ({ stdout: "ARTIFACT_PATH=/tmp/not-trusted.md\n", stderr: "", code: 0, killed: false });
const malformedResult = await second.tools[0].execute(
  "tool-call-3",
  { skill: "code-reviewer", task: "Review", cwd: root },
  undefined,
  undefined,
  { cwd: root },
);
assert.equal(malformedResult.isError, true);
assert.equal(malformedResult.details.status, "failed");
assert.equal(malformedResult.details.artifactPath, undefined);

if (previousAgentDir === undefined) delete process.env.PI_CODING_AGENT_DIR;
else process.env.PI_CODING_AGENT_DIR = previousAgentDir;

console.log("skill tmux runner tests passed");
