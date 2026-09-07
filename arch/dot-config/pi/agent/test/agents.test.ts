import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import registerAgents, { parseLauncherOutput } from "../extension-src/agents/index.ts";
import { agentNames, promptPath, startPanePath, waitPath } from "../extension-src/agents/config.ts";

const root = new URL("..", import.meta.url).pathname;
const temp = mkdtempSync(join(tmpdir(), "pi-agents-unit-"));
const previousChild = process.env.PI_AGENT_CHILD;
const previousLegacyChild = process.env.PI_CHILD_RUNNER_SKILL;
delete process.env.PI_AGENT_CHILD;
delete process.env.PI_CHILD_RUNNER_SKILL;

const assignment = {
  agent: "reviewer", task: "Review the patch",
  context: "src/a.ts changed; base abc123; type check failed with example error",
  constraints: "Read-only; do not install packages",
  expected_output: "Actionable findings with file/line references; report unverified checks",
};
const ctx = { cwd: root };
const quote = (text: string) => `'${text.replaceAll("'", "'\\''")}'`;
const artifact = join(temp, "reviewer's report.md");
const success = join(temp, "run.success");
const failure = join(temp, "run.failure");
const launched = {
  stdout: `noise\nARTIFACT_PATH=${quote(artifact)}\nSUCCESS_SENTINEL=${quote(success)}\nFAILURE_SENTINEL=${quote(failure)}\n`,
  stderr: "", code: 0, killed: false,
};
const finished = { stdout: "OVERALL='success'\n", stderr: "", code: 0, killed: false };

function runtime() {
  const tools: any[] = [];
  const calls: any[] = [];
  const hooks: string[] = [];
  const pi = {
    registerTool(tool: any) { tools.push(tool); },
    on(name: string) { hooks.push(name); },
    exec(command: string, args: string[], options: any) {
      calls.push({ command, args, options });
      return command === startPanePath ? launched : finished;
    },
  };
  registerAgents(pi);
  return { pi, tools, calls, hooks };
}

try {
  for (let i = 0; i < 2; i++) {
    const r = runtime(); // Registration also works after a reload/rebind.
    assert.equal(r.tools.length, 1);
    const tool = r.tools[0];
    assert.equal(tool.name, "run_agent");
    assert.deepEqual(r.hooks, [], "no manual input interception or read redirection");
    assert.deepEqual(tool.parameters.properties.agent.enum, ["explorer", "implementer", "internet-researcher", "reviewer"]);
    assert.deepEqual(tool.parameters.required, ["agent", "task", "context", "constraints", "expected_output"]);
    assert.equal(tool.parameters.additionalProperties, false);
    assert.equal(tool.parameters.properties.noWait, undefined);
    assert.equal(tool.parameters.properties.cwd, undefined, "cwd comes from the current main session");
  }

  for (const marker of ["PI_AGENT_CHILD", "PI_CHILD_RUNNER_SKILL"]) {
    process.env[marker] = "1";
    assert.equal(runtime().tools.length, 0, `${marker}: children have no delegation tool`);
    delete process.env[marker];
  }

  const r = runtime();
  const tool = r.tools[0];
  const controller = new AbortController();
  const result = await tool.execute("id", assignment, controller.signal, undefined, ctx);
  assert.deepEqual(result.details, { agent: "reviewer", cwd: root.replace(/\/$/, ""), artifactPath: artifact });
  assert.match(result.content[0].text, /Read the report/);
  assert.equal(r.calls.length, 2);
  const launch = r.calls[0];
  assert.equal(launch.command, startPanePath);
  assert.equal(launch.args[launch.args.indexOf("--role-prompt") + 1], promptPath("reviewer"));
  assert.equal(launch.args[launch.args.indexOf("--model") + 1], "gpt-5.6-luna");
  for (const field of ["task", "context", "constraints", "expected_output"] as const) {
    assert(launch.args[launch.args.indexOf("--task") + 1].includes(assignment[field]), `${field} is preserved in the handoff`);
  }
  assert.equal(launch.options.signal, controller.signal);
  assert.equal(r.calls[1].command, waitPath);
  assert.deepEqual(r.calls[1].args, ["--success", success, "--failure", failure, "--timeout", "1800", "--poll", "1"]);

  for (const agent of agentNames) {
    const r = runtime();
    await r.tools[0].execute("id", { ...assignment, agent }, undefined, undefined, ctx);
    const args = r.calls[0].args;
    assert.equal(args.includes("--workspace-lock"), agent === "implementer");
  }

  for (const field of ["task", "context", "constraints", "expected_output"] as const) {
    for (const value of [undefined, "", "  \n", 5]) {
      const r = runtime();
      await assert.rejects(r.tools[0].execute("id", { ...assignment, [field]: value }, undefined, undefined, ctx), new RegExp(field));
      assert.equal(r.calls.length, 0);
    }
  }
  for (const agent of ["planner", "code-reviewer", "review-orchestrator", "plan-reviewer", "toString", ""]) {
    await assert.rejects(tool.execute("id", { ...assignment, agent }, undefined, undefined, ctx), /Invalid subagent role/);
  }
  process.env.PI_AGENT_CHILD = "1";
  const count = r.calls.length;
  await assert.rejects(tool.execute("id", assignment, undefined, undefined, ctx), /cannot delegate/);
  assert.equal(r.calls.length, count, "execution guard also rejects nested calls");
  delete process.env.PI_AGENT_CHILD;
  controller.abort();
  await assert.rejects(tool.execute("id", assignment, controller.signal, undefined, ctx), /cancelled before launch/);
  assert.equal(r.calls.length, count);

  const errors = [
    { name: "launch exit", launch: { ...launched, code: 42, stderr: "pane failed" }, wait: finished, match: /pane failed/ },
    { name: "launch killed", launch: { ...launched, killed: true }, wait: finished, match: /launch failed/ },
    { name: "missing paths", launch: { ...launched, stdout: "ARTIFACT_PATH=/unquoted\n" }, wait: finished, match: /sentinel paths/ },
    { name: "timeout", launch: launched, wait: { ...finished, code: 1, stdout: "timeout" }, match: /timeout.*pane may still be running/ },
    { name: "wait cancelled", launch: launched, wait: { ...finished, killed: true }, match: /did not complete/ },
  ];
  for (const test of errors) {
    const r = runtime();
    r.pi.exec = (command) => command === startPanePath ? test.launch : test.wait;
    await assert.rejects(r.tools[0].execute("id", assignment, undefined, undefined, ctx), test.match, test.name);
  }
  writeFileSync(`${failure}.reason`, "workspace-lock-held\n");
  const failed = runtime();
  failed.pi.exec = (command) => command === startPanePath ? launched : { ...finished, code: 1 };
  await assert.rejects(failed.tools[0].execute("id", assignment, undefined, undefined, ctx), /workspace-lock-held/);

  assert.equal(parseLauncherOutput(launched.stdout).ARTIFACT_PATH, artifact);
  assert.deepEqual(parseLauncherOutput("ARTIFACT_PATH='/tmp/a' evil\nOTHER='x'\n"), {});
  assert.deepEqual(readdirSync(join(root, "agents")).sort(), agentNames.map((name) => `${name}.md`).sort());
  assert.deepEqual(readdirSync(join(root, "skills")).sort(), ["specifier"]);
  for (const agent of agentNames) {
    const prompt = readFileSync(promptPath(agent), "utf8");
    assert(!prompt.startsWith("---"), "roles must not be discoverable Pi skills");
    assert(prompt.length > 200);
    assert.doesNotMatch(prompt, /run_skill|review-orchestrator|plan-reviewer/);
  }
} finally {
  if (previousChild === undefined) delete process.env.PI_AGENT_CHILD;
  else process.env.PI_AGENT_CHILD = previousChild;
  if (previousLegacyChild === undefined) delete process.env.PI_CHILD_RUNNER_SKILL;
  else process.env.PI_CHILD_RUNNER_SKILL = previousLegacyChild;
  rmSync(temp, { recursive: true, force: true });
}
console.log("agent tool tests passed");
