# Shared skill scripts

Shared low-level scripts for tmux-managed bundled Pi skills.

## Files

- `start-bg-pane.sh` — starts a child Pi pane, validates inputs, creates `.agents/` directories, and manages logs/sentinels.
- `wait-for-children.sh` — waits for one or more child runs and prints a key=value summary.

The Pi extension owns skill policy and calls these helpers directly. Skill metadata such as artifact directory, prompt template, and workspace locking lives in `extension-src/skill-tmux/skills.ts`.

## Pane starter contract

Call:

```sh
skills/scripts/start-bg-pane.sh \
  --skill NAME \
  --artifact-dir research|plans|specs|reviews|impl-reports \
  --prompt-template FILE \
  --task TEXT \
  --cwd DIR
```

Optional arguments:

- Pi routing: `--provider`, `--model`, `--thinking`
- runner behavior: `--timeout`, `--pi-bin`, `--workspace-lock`, `--artifact`

The helper starts the pane and returns immediately with:

- `ARTIFACT_PATH`
- `SUCCESS_SENTINEL`
- `FAILURE_SENTINEL`

Callers that need synchronous behavior should pass the sentinel paths to `wait-for-children.sh`.

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

The finish helper marks failure when a successful finish has no primary artifact, and the generated runner marks failure if Pi exits without either sentinel.

Successful finishes close the child pane by default. Failed runs keep the pane open for diagnostics.

## Locks

Callers can pass `--workspace-lock` to acquire a non-blocking `flock` from the canonical working directory before starting child Pi. If another locked run is active for the same workspace, the helper writes a `workspace-lock-held` failure artifact, failure sentinel, and failure reason.

## Waiting for children

`wait-for-children.sh` accepts repeated sentinel pairs plus timeout controls:

```sh
skills/scripts/wait-for-children.sh \
  --success PATH --failure PATH \
  [--success PATH --failure PATH ...] \
  --timeout SECONDS --poll SECONDS
```

It exits 0 when all children succeeded and non-zero otherwise.
