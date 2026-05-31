---
name: web-search
description: Provide web search query design, source discovery, result triage, and fetch-decision methodology.
---

# Web Search Query and Source Discovery Methodology

## Objective

Provide practical methodology for discovering relevant web sources through search queries, source selection, result triage, and fetch decisions.

This skill does not own the full research workflow, final synthesis, research-file output, or final conclusions. Those responsibilities belong to the calling agent, usually `internet_research`.

## Role boundary

- This skill helps with web query design, source discovery, result triage, and fetch decisions.
- This skill does not decide the final research structure, write research files, or produce final conclusions.
- The calling agent owns orchestration, evaluation depth, synthesis, uncertainty handling, and output format.

## Search query design

- Use broad exploratory queries to map the topic.
- Use exact-match queries for specific errors, phrases, APIs, names, or claims.
- Use English queries for language-neutral technical topics.
- Use local-language queries when the topic is region-specific.
- Use synonyms, alternate product names, historical names, and related terminology.
- Use date-constrained queries for recent or time-sensitive claims.
- Use site-specific queries for official docs, GitHub, standards bodies, issue trackers, government/statistical sources, or known authoritative domains.

## Source category selection

Choose source categories based on the question:

- Official documentation or vendor announcements
- Source repositories, issues, pull requests, and release notes
- Standards, specifications, RFCs, or protocol documents
- Academic papers or preprints
- Government, statistical, or regulatory sources
- News reports
- Forums, Q&A, and community discussions
- Known URLs provided by the caller

## Result triage

Prefer sources that are:

- Primary or close to primary
- Recent enough for the claim
- Specific to the question
- Transparent about evidence, dates, and authorship
- Corroborated by other reliable sources

Avoid sources that are:

- SEO-oriented summaries with no primary references
- Outdated for version-sensitive topics
- Anonymous or unverifiable when authority matters
- Pure opinion presented as fact
- Duplicated syndications of the same original article

## Fetch decision

- Use search snippets only when they are sufficient for a low-risk, non-specific fact.
- Fetch the page when exact wording, dates, API behavior, claims, or citations matter.
- Prefer known authoritative URLs when the caller provides them.
- Use full-content extraction for long articles, specs, docs, or pages where snippets are incomplete.
- Avoid fetching sources that are clearly irrelevant or low quality.
