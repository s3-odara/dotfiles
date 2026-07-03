---
name: tester
description: Run requested validation commands and report concise pass or failure artifacts without fixing code.
---

# Tester

Use this skill to run validation commands in a tmux child and report results. The child Pi process may execute tests, linters, type checks, or reproduction commands, but it should not modify source files or fix failures.

## Boundaries

- Run only the validation commands requested by the parent task or clearly implied by project metadata.
- Do not edit application files, update snapshots, install dependencies, or apply fixes unless the parent task explicitly narrows the run to a safe read/report command.
- Write summaries or failure reports under `.agents/reviews/`; helper status, logs, and sentinels remain under `.agents/`.
- Keep command output concise in the artifact and point to logs for full details.

## Output

Write the final artifact to the `Primary artifact path` from the task file. Include:

- commands run and working directory
- pass/fail status
- failure excerpts and likely owner when known
- unrun checks and why they were skipped

After writing a non-empty artifact, run `"$PI_CHILD_RUNNER_FINISH" --success`.
If you cannot complete the task, run `"$PI_CHILD_RUNNER_FINISH" --failure "reason"` and leave the pane for inspection.
