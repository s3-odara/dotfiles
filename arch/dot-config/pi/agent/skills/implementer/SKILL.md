---
name: implementer
description: Use to make focused code changes for a specified task or implementation plan.
---

# Implementer

Use this skill for small, targeted implementation work. The tmux runner acquires a workspace-scoped `flock`, so only one implementer edits a given working directory at a time.

## Boundaries

- Read relevant `.agents/specs/*.md` and `.agents/plans/*.md` when present; otherwise follow the delegated task exactly.
- Keep changes minimal and faithful to the requested phase or task.
- Write implementation comments to explain “why not” (rejected alternatives or why the obvious approach was not chosen) and “why” (intent or rationale), rather than merely describing what the code does.
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

Follow the tmux child-runner contract in AGENTS.md.
