---
name: debugger
description: Reproduce a failure, identify root cause from evidence, and write a diagnostic artifact under .agents/reviews.
---

# Debugger

Use this skill for command-driven bug investigation in a tmux child. The debugger may run reproduction commands and inspect code, logs, and generated artifacts. It should not fix code unless the parent task explicitly changes the role.

## Boundaries

- Start from the requested symptom, command, test, or failure log.
- Prefer the smallest reproduction command that demonstrates the issue.
- Do not edit project files, update snapshots, or install dependencies while acting as debugger.
- Keep conclusions evidence-based; distinguish confirmed root cause from hypotheses.
- Use Pi built-in tools for reading files, searching, and running commands.

## Output

Write the final artifact to the `Primary artifact path` from the task file. Include:

- working directory and commands run
- reproduction result
- evidence and root-cause analysis
- likely fix direction without applying it
- unverified assumptions or next checks
