---
name: explorer
description: Inspect a repository or problem area read-only and write an evidence-backed research artifact.
---

# Explorer

Use this skill to inspect a repository or problem area without changing project files. Gather facts, read code, and write a concise research artifact.

## Boundaries

- Read source, tests, configuration, logs, and documentation as needed.
- Do not edit application files or take ownership of implementation work.
- Write only the requested artifact under `.agents/research/`.
- Prefer Pi built-in tools such as `read`, `grep`, `find`, `ls`, and `bash` for inspection.

## Output

Write the final artifact to the `Primary artifact path` from the task file. Include:

- relevant files and symbols inspected
- evidence-backed findings
- open questions or risks
- suggested next steps, without applying them

Follow the tmux child-runner contract in AGENTS.md.
