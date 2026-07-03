---
name: plan-reviewer
description: Review plans and specs read-only for ambiguity, sequencing, scope, and validation gaps.
---

# Plan Reviewer

Use this skill for read-only review of implementation plans, specs, or task breakdowns. The child Pi process should identify ambiguity, missing validation, scope creep, and ordering risks without editing the plan.

## Boundaries

- Read only the relevant plan, spec, and nearby context needed for review.
- Do not edit plans, specs, source files, or project configuration.
- Write only the requested review artifact under `.agents/reviews/`; helper status, logs, and sentinels remain under `.agents/`.
- Prefer focused improvements over broad redesign.

## Output

Write the final artifact to the `Primary artifact path` from the task file. Include:

- reviewed plan/spec paths
- blocking ambiguities or missing acceptance criteria
- test and sequencing gaps
- concise recommended changes
- verdict on whether the plan is ready

After writing a non-empty artifact, run `"$PI_CHILD_RUNNER_FINISH" --success`.
If you cannot complete the task, run `"$PI_CHILD_RUNNER_FINISH" --failure "reason"` and leave the pane for inspection.
