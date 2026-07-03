# Shared skill scripts

Shared tmux child-runner contract used by tmux-managed bundled skills.

## Files

- `spawn-tmux-child-common.sh` — validates inputs, creates `.agents/` output directories, starts a detached tmux session, and records status, logs, and sentinels for one child Pi run.
- `tmux-managed-skills.tsv` — central manifest of skills that should be intercepted for tmux execution. Native Pi skills such as `web-search` are intentionally absent so Pi can expand them normally.
- `spawn-skill-tmux-child.sh` — central launcher. It reads the manifest, dispatches normal skills to the common helper, and dispatches coordinator skills to `coordinators/<skill>.sh`.
- `coordinators/review-orchestrator.sh` — coordinator implementation that launches `code-reviewer` through the same central launcher and aggregates the resulting artifact.
- `wait-for-children.sh` — blocks until one or more tmux children finish, then prints a JSON summary. Accepts multiple `--run-id` arguments plus `--timeout` / `--poll`. Exits 0 when all children succeeded, non-zero otherwise.

## Contract

Call `spawn-skill-tmux-child.sh --skill NAME --task TEXT --cwd DIR`. The launcher accepts optional Pi routing hints: `--provider`, `--model`, and `--thinking`, plus `--timeout`, `--pi-bin`, `--keep-pane`, and `--auto-exit`. The internal common helper still owns prompt-template, artifact-dir, and lock arguments; keeping those internal prevents call sites from bypassing the manifest policy.

Manifest `normal` skills print a status JSON path on stdout. Callers can derive the run-id from that path and use `wait-for-children.sh` to wait for sentinels. Manifest `coordinator` skills own their child polling internally and print the final aggregate artifact path instead.

Runs use detached tmux sessions named:

```text
pi-<skill>-<task-slug>-<YYYYMMDDHHMMSS>-<pid>-<random>
```

All generated files stay under the target workspace `.agents/` tree. The helper creates `research`, `plans`, `specs`, `reviews`, `impl-reports`, `logs`, `status`, and `locks` directories.

Each run writes:

- status JSON: `.agents/status/<run-id>.json`
- stdout log: `.agents/logs/<run-id>.stdout.log`
- stderr log: `.agents/logs/<run-id>.stderr.log`
- runner log: `.agents/logs/<run-id>.runner.log`
- success sentinel: `.agents/status/<run-id>.success`
- failure sentinel: `.agents/status/<run-id>.failure`
- primary artifact: supplied with `--artifact`, or generated under `.agents/<artifact-dir>/`

The helper treats timeout, non-zero child exit, and missing/empty primary artifact as failures. Success exits the tmux session by default; failures keep the pane for diagnostics unless the caller explicitly changes the flags in a later wrapper.

## Locks

Write-capable skills use manifest-declared `--lock-key workspace` to acquire a `flock` file before the child Pi process starts. The helper derives a lock filename from the canonical working directory and stores it under `.agents/locks/`. If the lock cannot be acquired within `--lock-timeout`, the run writes a failure artifact, status JSON, and failure sentinel without starting the child process.
