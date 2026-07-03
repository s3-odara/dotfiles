# Shared skill scripts

Shared tmux child-runner contract used by tmux-managed bundled skills.

## Files

- `start-bg-pane.sh` — validates inputs, creates `.agents/` output directories, starts an interactive pane in the shared tmux `agent` window, and records logs and sentinels for one child Pi run.
- `run-skill-background.sh` — central launcher for bundled tmux-managed skills. Native Pi skills such as `web-search` are intentionally not routed here so Pi can expand them normally.
- `wait-for-children.sh` — blocks until one or more tmux children finish, then prints a key=value summary. Accepts repeated `--success PATH --failure PATH` sentinel pairs plus `--timeout` and `--poll`. Exits 0 when all children succeeded, non-zero otherwise.

## Contract

Call `run-skill-background.sh --skill NAME --task TEXT --cwd DIR`. The launcher accepts optional Pi routing hints: `--provider`, `--model`, and `--thinking`, plus `--timeout`, `--pi-bin`, and `--no-wait`. The internal pane starter still owns prompt-template and artifact-dir arguments; keeping those internal prevents call sites from bypassing launcher policy.

By default the launcher waits for completion and prints only `ARTIFACT_PATH='quoted value'` on success. On failure or timeout it exits non-zero and writes diagnostics to stderr. With `--no-wait`, it starts the pane and returns immediately with `ARTIFACT_PATH`, `SUCCESS_SENTINEL`, and `FAILURE_SENTINEL` for future watcher/extension use.

Runs use detached tmux sessions named:

```text
pi-<skill>-<task-slug>-<YYYYMMDDHHMMSS>-<pid>-<random>
```

All generated files stay under the target workspace `.agents/` tree. The helper creates `research`, `plans`, `specs`, `reviews`, `impl-reports`, `logs`, `status`, and `locks` directories.

Each run writes:

- runner log: `.agents/logs/<run-id>.runner.log`
- success sentinel: `.agents/status/<run-id>.success`
- failure sentinel: `.agents/status/<run-id>.failure`
- failure reason: `.agents/status/<run-id>.failure.reason`
- primary artifact: supplied with `--artifact`, or generated under `.agents/<artifact-dir>/`

The helper treats non-zero child exit and missing/empty primary artifact as failures. Success closes the pane by default; failures keep the pane for diagnostics.

## Locks

`implementer` panes acquire a non-blocking `flock` derived only from the canonical working directory before the child Pi process starts. If another implementer is already active for the same workspace, the run writes a `workspace-lock-held` failure artifact, failure sentinel, and failure reason without starting the child process.
