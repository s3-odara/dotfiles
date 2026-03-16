---
name: web-research-router
description: Route web research tasks between built-in Web search and local Playwright Firefox automation. Use when Codex needs to investigate current information, documentation, news, websites, or rendered page behavior, and should prefer normal Web search first but switch to Firefox for JavaScript-rendered pages, scrolling, clicks, form input, post-login flows, or other interactive states that static fetching cannot capture reliably.
---

# Web Research Router

Use built-in Web search by default for discovery, current information, and source-backed answers. Escalate to local Playwright Firefox only when interaction or rendered state matters.
This skill is a router, not the place for Playwright CLI details. When browser automation is needed, switch to the `playwright` skill for the concrete commands and interaction loop.

## Default Path

Start here unless the task clearly depends on browser state:

1. Start with built-in Web search for discovery, freshness, and source collection.
2. Use direct page fetches only if the answer depends on a specific page and the page is likely static.
3. Switch to Playwright Firefox when the page requires JavaScript, user actions, scrolling, waiting for hydration, or validation of rendered DOM state.

Use built-in Web search when the task is mainly:

- finding current information, news, prices, schedules, or official documentation
- comparing multiple sources or returning source links
- discovering which URLs matter before visiting them directly
- answering a question that does not depend on interactive browser state

## Escalate To Firefox

Use Playwright Firefox when any of these are true:

- the user explicitly asks to use Firefox or Playwright
- the target page is a SPA or otherwise JavaScript-rendered
- content appears only after clicks, typing, scrolling, or waiting
- the task requires checking post-login or post-navigation UI state
- static fetches miss important content or page structure
- the task requires extracting rendered DOM, visible text, or links after interaction

Prefer opening a known URL directly in Firefox. Avoid driving a public search engine with Playwright unless normal Web search is insufficient and browser interaction is part of the task.

Use Firefox automation when you already know the target URL and Web search or static fetches are not enough, such as:

- confirming the final rendered title or URL
- sampling visible text from a JavaScript-rendered page
- checking content that appears only after hydration, waiting, or interaction
- inspecting rendered links or visible DOM state after the page settles

## Firefox Handoff

When Firefox automation is needed:

1. Keep the browser headless unless visual debugging is necessary.
2. Keep `web-research-router` as the decision layer.
3. Load the `playwright` skill and use its CLI-first workflow for open, snapshot, interaction, and re-snapshot.
4. Open the known target URL directly whenever possible.
5. Wait only as much as needed to stabilize the relevant content.
6. Extract the minimum useful output: title, final URL, visible text summary, and relevant links or selectors.
7. Return concise findings and mention that Firefox automation was used.

## Guardrails

- Do not replace mandatory built-in Web browsing with Firefox when freshness verification or source attribution is the main need.
- Do not automate public search engines by default when built-in Web search can discover the same pages more reliably.
- Keep Firefox as a targeted fallback for rendered-page verification and interaction-heavy tasks.
- If Playwright or Firefox is unavailable, fall back to built-in Web search and state the limitation briefly.
