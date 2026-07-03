# Pi agent conventions

- The workspace is an isolated container; normal in-container system changes are acceptable.

## tmux child-runner contract

For tmux-managed skills, write the artifact to `Primary artifact path`, then run:

```sh
"$PI_CHILD_RUNNER_FINISH" --success
```

On failure, run:

```sh
"$PI_CHILD_RUNNER_FINISH" --failure "reason"
```

and leave the pane for inspection. Read-only skills must not edit project files or run mutating commands.

## Launching child skills

- Coordinator skills may launch children with `"$PI_CHILD_RUNNER_SKILLS_SCRIPTS_DIR/run-skill-background.sh"`.
- The launcher waits by default and prints `ARTIFACT_PATH=<value>` on success.
- Source only `ARTIFACT_PATH` from trusted launcher output; do not eval arbitrary child text.
- Treat launcher failures, missing artifacts, non-success statuses, timeouts, and child launch failures as diagnostics.
