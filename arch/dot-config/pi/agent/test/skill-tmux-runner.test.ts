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
assert.match(result.text, /spawn-skill-tmux-child\.sh/);
assert.match(result.text, /--skill 'code-reviewer'/);
assert.match(result.text, /Review this diff\nwith details/);
assert.match(result.text, /wait-for-children\.sh/);

const coordinatorResult = await second.handlers.input(
  { source: "interactive", text: "/skill:review-orchestrator Review this branch" },
  { cwd: root, ui: { notify() {} } },
);
assert.equal(coordinatorResult?.action, "transform");
assert.match(coordinatorResult.text, /spawn-skill-tmux-child\.sh/);
assert.match(coordinatorResult.text, /--skill 'review-orchestrator'/);
assert.match(coordinatorResult.text, /artifact_path=\$\(/);
assert.doesNotMatch(coordinatorResult.text, /wait-for-children\.sh/);
assert.doesNotMatch(coordinatorResult.text, /status_json=/);

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
