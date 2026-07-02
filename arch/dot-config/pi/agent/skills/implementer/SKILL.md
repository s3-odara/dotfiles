---
name: implementer
description: Make focused code changes in a tmux child and write an implementation report under .agents/impl-reports.
---

# Implementer

Use this skill for small, targeted implementation work. The wrapper acquires a workspace-scoped `flock` before the child Pi process starts so only one implementer child edits a given working directory at a time.

## Boundaries

- Read relevant `.agents/specs/*.md` and `.agents/plans/*.md` when present; otherwise follow the delegated task exactly.
- Keep changes minimal and faithful to the requested phase or task.
- Edit files only in the intended working directory and generated `.agents/` artifact tree.
- Respect container/user instructions; do not stage, commit, push, install unrelated dependencies, or broaden scope unless explicitly requested.
- Use Pi built-in tools for file and shell work.

## Output

Write the final artifact to the `Primary artifact path` from the task file. It must start with:

```text
# Implementation Report:
```

Include:

- changed files
- what was implemented
- validation run and results
- remaining issues or risks
