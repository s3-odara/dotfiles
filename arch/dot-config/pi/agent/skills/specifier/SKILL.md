---
name: specifier
description: Use when the user asks to record design decisions in a plan or specification.
---

Use the main conversation to record decisions in a concise, human-readable document.
Do not delegate the writing, reopen settled decisions, or invent new requirements.
Separate agreed decisions from proposals, assumptions and open questions. A written
proposal is not user approval.

Ask only about ambiguities that materially affect scope, external behavior, risk,
or hard-to-reverse decisions. Otherwise follow existing conventions and state
consequential assumptions.

For a modest change, a plan in `.agents/plans/<topic>.md` is usually enough. For a
larger change, add `.agents/specs/<topic>.md` when requirements need a separate view;
link the plan to it rather than copying it. Respect an agreed path or existing document.
Write in polite Japanese and use only the sections that help:

- Purpose, scope and non-goals
- Chosen approach and important reasons or trade-offs
- Observable completion criteria
- Proposals, assumptions and open questions

A spec describes intended behavior and constraints; a plan records the implementation
approach. Include execution steps only where they clarify the approach or dependencies,
not an exhaustive edit recipe. Do not require FAC numbering or a separate QA document.
Stop after the requested documentation; do not automatically start implementation.
