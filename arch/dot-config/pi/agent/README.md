# Pi agent

It contains the local Pi agent setup: settings, themes, extension code, bundled skills, tmux child-runner scripts, and tests.

## plugins

```sh
pi install npm:pi-mcp-adapter
pi install npm:@spences10/pi-lsp
```

## Layout

- `settings.json` — Pi agent settings.
- `themes/` — Pi themes.
- `extensions/` — Pi auto-discovered extension entry points.
- `extension-src/` — extension implementation modules kept outside auto-discovery.
  - `osc99-notify/` — OSC99 notification formatting and event registration.
  - `webfetch/` — constrained HTTP/HTTPS URL fetch tool.
  - `skill-tmux/` — `/skill:name` tmux routing, `run_skill`, and tmux-skill discovery helpers.
- `skills/` — bundled tmux skills and native prompt-style skills.
- `skills/scripts/` — tmux pane starter and wait helper.
- `test/` — unit and contract tests run by `npm test`.
- `APPEND_SYSTEM.md` — additional workspace instructions appended to the system prompt.

## MCP

`arch/dot-config/mcp/mcp.json` stows to `~/.config/mcp/mcp.json`. It lists the candidate remote MCP servers `context7`, `deepwiki`, `exa`, and `parallel-search` using `url` entries and environment-variable header references. It stores no secrets.

Pi does not launch MCP servers directly from this file. The installed `pi-mcp-adapter` package reads the shared MCP config and handles discovery/connection. Do not set `command: "pi-mcp-adapter"` in the MCP config.

## Skills

Tmux-managed bundled skills:

- `review-orchestrator`
- `implementer`
- `explorer`
- `internet-researcher`
- `code-reviewer`
- `plan-reviewer`

Native prompt-style skills:

- `operator`
- `delegator`
- `planner`
- `specifier`

Tmux-managed skill metadata lives in `extension-src/skill-tmux/skills.ts`. Shared tmux runner details live in `skills/scripts/README.md`.

## OSC99 and webfetch

OSC99 notifications are emitted for Pi events available through the local Pi 0.80.2 extension API: assistant message completion, session idle after a prompt, and provider/tool errors. When `TMUX` is set, passthrough wraps OSC99 twice by default. Override with `PI_CODING_KIT_OSC99_TMUX_LAYERS=0`, `1`, or `2` if needed.

`webfetch` fetches a specific HTTP or HTTPS URL as text. It is not a search tool. It enforces protocol validation, timeout, maximum response bytes, and manual redirect limits.

## Validation

```sh
npm test
```

The suite covers OSC99 formatting, `webfetch`, tmux skill launching, sentinel waiting, and bundled skill contracts. Set `PI_CODING_KIT_TEST_NETWORK=1` to include the optional `https://example.com/` smoke fetch.
