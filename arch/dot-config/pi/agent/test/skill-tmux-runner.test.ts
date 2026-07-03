import assert from "node:assert/strict";
import registerSkillTmuxRunner from "../extension-src/skill-tmux-runner.ts";

const root = new URL("..", import.meta.url).pathname;
const previousAgentDir = process.env.PI_CODING_AGENT_DIR;
process.env.PI_CODING_AGENT_DIR = root;

function makePi() {
  const handlers: Record<string, (...args: any[]) => unknown> = {};
  return {
    handlers,
    pi: {
      on(eventName: string, handler: (...args: any[]) => unknown) {
        handlers[eventName] = handler;
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

if (previousAgentDir === undefined) delete process.env.PI_CODING_AGENT_DIR;
else process.env.PI_CODING_AGENT_DIR = previousAgentDir;

console.log("skill tmux runner tests passed");
