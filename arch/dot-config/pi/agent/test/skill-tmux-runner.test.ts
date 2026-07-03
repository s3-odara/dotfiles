import assert from "node:assert/strict";
import { join } from "node:path";
import registerSkillTmuxRunner from "../extension-src/skill-tmux-runner.ts";

const root = new URL("..", import.meta.url).pathname;
const previousAgentDir = process.env.PI_CODING_AGENT_DIR;
process.env.PI_CODING_AGENT_DIR = root;

function makePi() {
  const handlers: Record<string, (...args: any[]) => unknown> = {};
  const tools: any[] = [];
  return {
    handlers,
    tools,
    pi: {
      on(eventName: string, handler: (...args: any[]) => unknown) {
        handlers[eventName] = handler;
      },
      registerTool(tool: any) {
        tools.push(tool);
      },
    },
  };
}

const first = makePi();
registerSkillTmuxRunner(first.pi);
assert.equal(typeof first.handlers.input, "function", "first runtime should register input hook");

const second = makePi();
registerSkillTmuxRunner(second.pi);
assert.equal(typeof second.handlers.input, "function", "reload/rebind should register input hook again");
assert.equal(typeof second.handlers.tool_result, "function", "runtime should register tool_result hook");
assert.equal(second.tools.length, 1, "runtime should register exactly one tool");
assert.equal(second.tools[0].name, "run_skill");

const result = await second.handlers.input(
  { source: "interactive", text: "/skill:code-reviewer\nReview this diff\nwith details" },
  { cwd: root, ui: { notify() {} } },
);

assert.equal(result?.action, "transform");
assert.match(result.text, /run-skill-background\.sh/);
assert.match(result.text, /--skill 'code-reviewer'/);
assert.match(result.text, /Review this diff\nwith details/);
assert.doesNotMatch(result.text, /wait-for-children\.sh/);
assert.match(result.text, /launcher waits for the child to finish/);
assert.doesNotMatch(result.text, /ATTACH_TARGET/);
assert.match(result.text, /tmux window `agent`/);
assert.doesNotMatch(result.text, /node -e|JSON\.parse|status_json/);

const orchestratorResult = await second.handlers.input(
  { source: "interactive", text: "/skill:review-orchestrator Review this branch" },
  { cwd: root, ui: { notify() {} } },
);
assert.equal(orchestratorResult?.action, "transform");
assert.match(orchestratorResult.text, /run-skill-background\.sh/);
assert.match(orchestratorResult.text, /--skill 'review-orchestrator'/);
assert.match(orchestratorResult.text, /launch_output=/);
assert.doesNotMatch(orchestratorResult.text, /wait-for-children\.sh/);
assert.doesNotMatch(orchestratorResult.text, /artifact_path=\$\(/);

const nativeSkillResult = await second.handlers.input(
  { source: "interactive", text: "/skill:web-search Find sources" },
  { cwd: root, ui: { notify() {} } },
);
assert.equal(nativeSkillResult?.action, "continue");

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

const plannerRead = await second.handlers.tool_result(
  { toolName: "read", input: { path: join(root, "skills", "planner", "SKILL.md") }, content: [], details: {}, isError: false },
  { cwd: root },
);
assert.equal(plannerRead, undefined);

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
  return { stdout: "noise\nARTIFACT_PATH='/tmp/artifact.md'\n", stderr: "", code: 0, killed: false };
};
const successToolResult = await second.tools[0].execute(
  "tool-call-1",
  { skill: "code-reviewer", task: "Review this diff", cwd: root },
  signal,
  undefined,
  { cwd: "/should/not/use" },
);
assert.equal(execCalls.length, 1);
assert.match(execCalls[0].command, /run-skill-background\.sh$/);
assert.deepEqual(execCalls[0].args, ["--skill", "code-reviewer", "--task", "Review this diff", "--cwd", root]);
assert.equal(execCalls[0].args.includes("--no-wait"), false);
assert.equal(execCalls[0].options.signal, signal);
assert.equal(successToolResult.details.status, "success");
assert.equal(successToolResult.details.artifactPath, "/tmp/artifact.md");

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
