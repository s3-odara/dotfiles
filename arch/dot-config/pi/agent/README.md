# Pi daily-driver agent

This directory is stowed to `~/.config/pi/agent`. `PI_CODING_AGENT_DIR` must point there so Pi reads it. The agent directory is self-contained: extension code, skills, themes, settings, and validation scripts all live here in dotfiles. There is no external Pi package to install.

## Why these files live here

Pi loads `settings.json`, skills, themes, and optional model overrides from its agent directory. The extension entry, bundled tmux skills, native prompt-style skills, and validation scripts that previously lived in a separate standalone repository are integrated here because the kit is small and personal. JSON files have no comments, so this README records the non-obvious choices.

## Installation

1. Stow the dotfiles package as usual:

   ```sh
   make stow-arch
   ```

2. Ensure `tmux` is available. The bundled skills use only tmux and do not fall back to other multiplexers or terminal-specific panes.

3. Optional integrations are expected to be installed by the user environment, not by these dotfiles:

   - `@spences10/pi-lsp` for LSP
   - language servers for the languages you use

   MCP support is provided by the `pi-mcp-adapter` Pi package installed with `pi install npm:pi-mcp-adapter`.

Missing optional LSP/MCP pieces should be treated as warnings. They should not be turned into startup blockers because daily-driver use must still work for local tasks.

## Layout

- `extensions/` — Pi auto-discovered extension entry points only.
- `extension-src/` — internal extension implementation modules, kept outside Pi auto-discovery.
- `extension-src/osc99-notify/` — OSC99 notification formatting and event registration.
- `extension-src/webfetch/` — URL fetch tool with protocol, timeout, byte, and redirect controls.
- `extension-src/skill-tmux/` — manual `/skill:name` tmux rewriting, automatic `run_skill`, and shared tmux-skill discovery helpers.
- `skills/` — bundled Pi skills, native prompt-style skills, and the user-specific `web-search` methodology skill.
- `skills/scripts/` — central tmux-managed skill launcher, wait helper, and common child runner.
- `scripts/` — repository validation scripts.
- `test/` — unit and contract tests run via `npm test`.
- `AGENTS.md` — shared workspace and tmux child-runner conventions for Pi skills.
- `themes/`, `settings.json` — Pi agent configuration.

## MCP

`arch/dot-config/mcp/mcp.json` stows to `~/.config/mcp/mcp.json` and lists the required candidate servers: `context7`, `deepwiki`, `exa`, and `parallel-search`. It uses remote `url` entries plus environment-variable references for headers, and stores no secrets.

Pi itself does not launch MCP servers directly. The `pi-mcp-adapter` package reads this shared MCP config and connects to the remote HTTP endpoints. Install the adapter package with:

```sh
pi install npm:pi-mcp-adapter
```

The config intentionally does not use `command: "pi-mcp-adapter"`; the adapter binary is only a helper, while the installed Pi package owns MCP discovery and connection handling.

## LSP

The spec selects `@spences10/pi-lsp`. This dotfiles phase preserves that package decision in documentation instead of vendoring or installing it. Language server binaries are intentionally user-managed.

## Models

These dotfiles use Pi's built-in `opencode-go` and `openai-codex` providers instead of redefining them in `models.json`. For `opencode-go`, authenticate with Pi's native provider support (`/login opencode-go`, `auth.json`, or `OPENCODE_API_KEY` as documented by Pi). Do not set an `opencode-go` `baseUrl` override here; Pi already knows the native endpoint, and a literal `$OPENCODE_GO_BASE_URL` is not a valid URL at request time.

Child skills use Pi's default model unless the central launcher is explicitly invoked with `--provider`, `--model`, or `--thinking`.

## Skills

Native prompt-style skills replace the previous `prompts/` templates for:

- `operator`
- `delegator`
- `planner`
- `specifier`

They are intentionally not listed in `skill-tmux-runner.ts`, so explicit `/skill:operator`, `/skill:delegator`, `/skill:planner`, and `/skill:specifier` prompts fall through to Pi's native skill expansion instead of being launched in tmux.

Tmux-managed skills keep their role text close to the corresponding OpenCode prompts. Shared `run-skill-background.sh` and finish-helper instructions live in `AGENTS.md` instead of being repeated in each skill.

The eight tmux child roles live as bundled skills in this directory:

- `review-orchestrator`
- `implementer`
- `debugger`
- `explorer`
- `internet-researcher`
- `tester`
- `code-reviewer`
- `plan-reviewer`

`web-search` is retained here as a user-specific methodology skill. It is intentionally not handled by `skill-tmux-runner.ts`, so explicit `/skill:web-search` prompts fall through to Pi's native skill expansion instead of being launched in tmux. The Pi copy in this directory is the canonical location; the legacy OpenCode copy that previously lived under `arch/dot-agents/skills/web-search/` was removed to avoid a duplicate-skill collision with this one.

## OSC99 notifications

The extension emits OSC99 sequences to stdout for Pi events that are observable through the confirmed local Pi 0.80.2 extension API: assistant message completion, session idle after a prompt, and provider/tool errors. Tmux passthrough wraps OSC99 twice when `TMUX` is set; override with `PI_CODING_KIT_OSC99_TMUX_LAYERS=0`, `1`, or `2` if your terminal stack differs. The env var name is retained from the integrated kit for continuity.

## `webfetch` tool

`webfetch` fetches a specific HTTP or HTTPS URL as text. It is not a search tool. The implementation uses Node's built-in HTTP/HTTPS clients and enforces timeout, maximum body bytes, manual redirect limit, and HTTP/HTTPS protocol validation before each request and redirect. HTTP is allowed by policy; the tool intentionally does not perform address preflight or address-range blocking.

## Validation

```sh
npm test
```

The test suite runs unit tests for OSC99 formatting, `webfetch`, skill tmux launching, sentinel waiting, and bundled skill contracts. Set `PI_CODING_KIT_TEST_NETWORK=1` to include an optional public `https://example.com/` fetch smoke test.

## Acceptance / QA matrix

| Area | Expected result | Local check |
| --- | --- | --- |
| Native prompt-style skills | No tmux child-runner finish-helper assumptions | inspect `skills/{operator,delegator,planner,specifier}/SKILL.md` |
| Skills | Eight bundled tmux skills are referenced as Pi skills and write under `.agents/` | `npm test` |
| MCP | Required candidate servers are present and secrets are env refs only | inspect `~/.config/mcp/mcp.json` / `arch/dot-config/mcp/mcp.json` |
| LSP | `@spences10/pi-lsp` is user-installed; missing language servers are warnings | documented warning-only behavior |
| Models | Built-in `opencode-go` and `openai-codex` providers are selected without custom `models.json` overrides | inspect `settings.json` |
| Safety | Container isolation; no sandbox wrapper or permission popup requirement | inspect docs/skills |
| Webfetch/OSC99 | Policy and unit tests remain passing | `npm test` |
