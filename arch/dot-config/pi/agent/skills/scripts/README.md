# Shared skill scripts

Shared launcher scripts for tmux-managed bundled Pi skills.

## Files

- `run-skill-background.sh` — public launcher for bundled tmux-managed skills.
- `start-bg-pane.sh` — internal pane starter; validates inputs, creates `.agents/` directories, starts the child Pi pane, and manages logs/sentinels.
- `wait-for-children.sh` — waits for one or more child runs and prints a key=value summary.

Native Pi skills such as `operator`, `delegator`, `planner`, and `specifier` are not routed through these scripts.

## Launcher contract

Call:

```sh
skills/scripts/run-skill-background.sh --skill NAME --task TEXT --cwd DIR
```

Optional arguments:

- Pi routing: `--provider`, `--model`, `--thinking`
- runner behavior: `--timeout`, `--pi-bin`, `--no-wait`

The launcher owns artifact-dir and prompt-template selection so call sites cannot bypass skill policy.

By default, the launcher waits for completion and prints only:

```sh
ARTIFACT_PATH='quoted value'
```

On failure or timeout it exits non-zero and writes diagnostics to stderr.

With `--no-wait`, it starts the pane and returns immediately with:

- `ARTIFACT_PATH`
- `SUCCESS_SENTINEL`
- `FAILURE_SENTINEL`

## Outputs

Runs use IDs of this form:

```text
pi-<skill>-<task-slug>-<YYYYMMDDHHMMSS>-<pid>-<random>
```

All generated files are under the target workspace `.agents/` tree. The helper creates these directories as needed:

- `research`
- `plans`
- `specs`
- `reviews`
- `impl-reports`
- `logs`
- `status`
- `locks`

Each run writes:

- runner log: `.agents/logs/<run-id>.runner.log`
- success sentinel: `.agents/status/<run-id>.success`
- failure sentinel: `.agents/status/<run-id>.failure`
- failure reason: `.agents/status/<run-id>.failure.reason`
- primary artifact: supplied with `--artifact`, or generated under `.agents/<artifact-dir>/`

## Completion and failures

The parent launcher waits for success or failure sentinels. The finish helper marks failure when a successful finish has no primary artifact, and the generated runner marks failure if Pi exits without either sentinel.

Successful finishes close the child pane by default. Failed runs keep the pane open for diagnostics.

## Locks

`implementer` runs acquire a non-blocking `flock` from the canonical working directory before starting child Pi. If another implementer is active for the same workspace, the launcher does not start a child process. It writes a `workspace-lock-held` failure artifact, failure sentinel, and failure reason.

## Waiting for children

`wait-for-children.sh` accepts repeated sentinel pairs plus timeout controls:

```sh
skills/scripts/wait-for-children.sh \
  --success PATH --failure PATH \
  [--success PATH --failure PATH ...] \
  --timeout SECONDS --poll SECONDS
```

It exits 0 when all children succeeded and non-zero otherwise.
