# Shared skill scripts

Shared tmux child-runner contract used by bundled skill directories.

## Files

- `spawn-tmux-child-common.sh` — validates inputs, creates `.agents/` output directories, starts a detached tmux session, and records status, logs, and sentinels for one child Pi run.
- `skill-wrapper.sh` — shared per-skill wrapper implementation. Public skill-specific `scripts/spawn-tmux-child.sh` files remain executable stubs that call this wrapper.
- `wait-for-children.sh` — blocks until one or more tmux children finish, then prints a JSON summary. Accepts multiple `--run-id` arguments plus `--timeout` / `--poll`. Exits 0 when all children succeeded, non-zero otherwise.

## Contract

The common helper requires `--skill`, `--task`, `--cwd`, and `--prompt-template`. Optional flags pass Pi routing hints: `--provider`, `--model`, and `--thinking`. Current local Pi help confirms these flags, plus `--prompt-template`, `--no-session`, and `-p` for non-interactive child runs.

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

Write-capable wrappers can pass `--lock-key workspace` to acquire a `flock` file before the child Pi process starts. The helper derives a lock filename from the canonical working directory and stores it under `.agents/locks/`. If the lock cannot be acquired within `--lock-timeout`, the run writes a failure artifact, status JSON, and failure sentinel without starting the child process.
