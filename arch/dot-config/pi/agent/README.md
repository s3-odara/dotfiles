# Pi agent

Local Pi settings, extensions, agent roles, inline skills, themes and tests.

## Design

The main agent owns user communication, design discussions, plan/spec writing,
decisions, delegation and integration. Use subagents only when useful; there is no
mandatory workflow or review loop.

Plans and specs communicate decisions to both the user and implementation agents.
Keep agreed choices and their important reasons distinct from proposals and open
questions; writing a document does not make its contents approved. Surface
consequential unagreed choices before implementation instead of silently choosing.
A modest change usually needs only a plan; larger changes can separate requirements
into a spec and link to it from the plan. Prefer a readable approach and completion
criteria over an exhaustive edit recipe. Trivial work need not produce a document.

`run_agent` starts one independent tmux child, waits for its report and returns the
report path. The main agent must read it before continuing. Required arguments:

- `agent`: `explorer`, `implementer`, `internet-researcher` or `reviewer`.
- `task`: concrete objective and scope.
- `context`: relevant facts/decisions, file and report paths with summaries,
  prior commands/results/errors, and known unknowns.
- `constraints`: permitted changes, non-goals, prohibitions and approval boundaries.
- `expected_output`: deliverables, acceptance criteria and validation to report.

The working directory comes from the main session. Conversation and tool history
are **not** copied. Non-empty fields are required, but the main agent remains
responsible for the quality of the handoff. Children report missing information,
decisions and approvals to the main agent instead of delegating or asking the user.

Explorer is a scoped local lookup role using a lower-capability model. It returns
file/line locations and short source-backed answers, not design evaluations or
recommendations. The main agent treats its report as a navigation aid and verifies
the cited source before consequential judgments. A not-found report is limited to
the search performed; it does not prove absence. Explorer is optional, not a required
first phase.

Only the main agent has `run_agent`. Children are marked with `PI_AGENT_CHILD=1`;
both tool execution and the shell launcher reject child launches. Child Pi starts
with skill/template discovery disabled and delegation tools excluded. The role
body is injected as actual appended system-prompt text. MCP/LSP and other existing
extensions remain available. These controls prevent accidental nesting; unrestricted
shell access is not a security sandbox. Read-only roles are behavioral instructions,
not filesystem isolation.

There is no `run_skill`, Skill-read interception, manual subagent slash command,
`noWait`, nested orchestration or review-orchestrator. Ordinary skills remain
inline procedures for the current agent, not alternate child-launch routes.

## Layout

- `extensions/index.ts`: only auto-discovered extension entry point.
- `extension-src/agents/`: fixed role/model configuration and `run_agent`.
- `extension-src/agents/scripts/`: internal tmux launcher and sentinel waiter.
- `agents/*.md`: four role prompts; not discovered as Pi skills.
- `skills/`: short inline `specifier` guidance for recording plans and specifications.
- `extension-src/osc99-notify/`, `extension-src/webfetch/`: other local tools.
- `settings.json`, `themes/`, `APPEND_SYSTEM.md`: existing Pi configuration.
- `test/`: local tests with fake Pi/tmux, no model calls.

Model choices live in `extension-src/agents/config.ts`. Each subagent has an explicit
model preset; there is no separate planning agent.

## Runtime

Tmux children remain visible in the `agent` window for inspection/interaction.
Child reports go under the workspace's `.agents/{impl-reports,research,reviews}/`.
Main-authored plans/specifications normally go under `.agents/{plans,specs}/`.
Internal prompts, runner/finish scripts and sentinels go under `.agents/status/`;
launcher logs go under `.agents/logs/`.

Children write the assigned report and invoke `$PI_AGENT_FINISH --success` or
`--failure "reason"`. The helper verifies a non-empty report on success, updates
sentinels and closes successful panes. Failed panes stay open for inspection.
A delivered report can say `partial` or `blocked`; transport success does not mean
that all requested work was completed.

Calls wait up to 30 minutes. Cancellation/timeout stops waiting but does **not**
guarantee that the tmux child has stopped. Inspect the pane before retrying or editing
the workspace. Concurrent implementer children in the same canonical cwd are rejected
by a workspace lock. The main agent must also avoid concurrent edits in that workspace.

After updating this configuration, restart Pi (or `/reload` to rebind resources).
Stop old children before migrating; their deleted launch paths are not supported.
Do not replay old `run_skill` calls. There is intentionally no legacy launch alias.

## MCP

`arch/dot-config/mcp/mcp.json` stows to `~/.config/mcp/mcp.json`. It lists the remote
servers `context7`, `deepwiki`, `exa` and `parallel-search` using URL entries and
environment-variable header references, without storing secrets.

The installed `pi-mcp-adapter` reads the shared configuration. Pi does not launch
MCP servers directly from this file. Do not set `command: "pi-mcp-adapter"` there.
The existing `@spences10/pi-lsp` package supplies LSP tools.

## OSC99 and webfetch

OSC99 notifies only when the main interactive session emits `agent_settled`, after
retries, compaction and queued follow-ups have finished. Children and non-TUI modes
do not emit notifications. Under tmux, passthrough wraps OSC99 twice by default;
override with `PI_CODING_KIT_OSC99_TMUX_LAYERS=0`, `1` or `2`.

`webfetch` saves successful (2xx) HTTP/HTTPS responses and returns the path, byte
count, HTTP status and final URL. Non-2xx results, including unresolved redirects,
are errors and are not saved as downloads. A shared network timeout covers the
entire redirect chain; size and redirect limits also apply. It is not a search tool.

## Validation

```sh
npm test
```

Tests cover OSC99, webfetch, structured handoffs, parent-only delegation, actual
role injection, all four roles, launch/wait failures and implementer locking.
Set `PI_CODING_KIT_TEST_NETWORK=1` for the optional webfetch network smoke test.
