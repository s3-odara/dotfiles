---
name: explorer
description: Inspect a repository or problem area read-only and write an evidence-backed research artifact.
---

# Explorer

Use this skill to inspect a repository or problem area without changing project files. The child Pi process should gather facts, read code, and write a concise research artifact.

## Boundaries

- Read source, tests, configuration, logs, and documentation as needed.
- Do not edit application files or take ownership of implementation work.
- Write only the requested artifact under `.agents/research/`; the tmux helper owns logs and sentinels under `.agents/`.
- Prefer Pi built-in tools such as `read`, `grep`, `find`, `ls`, and `bash` for inspection.

## Output

Write the final artifact to the `Primary artifact path` from the task file. Include:

- relevant files and symbols inspected
- evidence-backed findings
- open questions or risks
- suggested next steps, without applying them

After writing a non-empty artifact, run `"$PI_CHILD_RUNNER_FINISH" --success`.
If you cannot complete the task, run `"$PI_CHILD_RUNNER_FINISH" --failure "reason"` and leave the pane for inspection.
