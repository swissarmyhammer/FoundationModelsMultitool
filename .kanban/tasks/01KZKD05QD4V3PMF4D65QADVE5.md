---
assignees:
- claude-code
position_column: todo
position_ordinal: '8380'
title: '[Multitool] Rename findAPIs → searchTools and cut the prompt surface to code-mode industry weight'
---
HUMAN-DIRECTED (2026-08-09). Two changes, one card: the discovery tool's name, and the size of the prompt surface.

## Why (researched, not guessed)

**The name.** `findAPIs` is our invention; the field has converged on "search". Anthropic's code-execution-with-MCP engineering post names the discovery tool `search_tools`. Cloudflare Code Mode's sandbox global is `codemode.search(query)` (paired with `codemode.describe(target)`). Our pairing should read `searchTools` / `runCode` — two camelCase verb-first siblings. "findAPIs" also mis-describes what comes back: it returns tool-functions, not APIs.

**The length.** Cloudflare's outer tool description is approximately one sentence — "write a JavaScript async arrow function" plus the connector namespace list. The typed declarations returned BY discovery carry the teaching. Our `sessionInstructions` is ~8 paragraphs and the descriptions repeat each other. The human's verdict: "this is all too wordy." Specific cut ordered: the pure-arithmetic exception sentence ("Only a request that is pure arithmetic or string work needs no functions at all...") — delete it entirely; no exemption clauses that give the model a reason to skip search.

## What

1. **Rename the wire name `findAPIs` → `searchTools`** everywhere the model can see it: the tool's `name`, both tool descriptions' references, `sessionInstructions`, sandbox `help()`/`docs()` text, `UnknownToolHint` text if it names the tool, sample snippets, worked examples, CLI output. Rename the Swift types to match (`FindAPIsTool` → `SearchToolsTool`, etc.) — no legacy alias, no deprecation shim; nothing outside this org consumes it yet.
2. **Compress the prompt surface hard.** Target: `sessionInstructions` ≤ 3 sentences; each tool description ≤ ~4 sentences. Keep the measured unconditional sequence — it is the one text intervention with a clean result (over-refusal 3/20→0/20, answered-without-calling 2/20→0/20): search first with the user's request, one runCode over the exact returned paths, answer only from what returned. Delete: the arithmetic exception, the "narrow follow-up searches come after" elaboration, the repeated "including the user's own data" claims (say it once), and any sentence that restates another surface's sentence. The typed signatures + runnable examples returned by searchTools remain the real teacher (that is where Cloudflare and Anthropic both put the weight).
3. **Draft to start from** (edit freely; constraints below are what is binding):
   - sessionInstructions: "This session's functions are mounted dynamically — searchTools is the only way to see them. For every request: call searchTools with the request itself, write one runCode snippet calling the exact tools.* paths it returns, and answer only from what the snippet returns. Search again for anything still missing; never guess a function name and never ask the user for data the tools can fetch."
   - searchTools description: "Describe the task in plain language; returns the relevant tool-functions with typed signatures and runnable examples. Call it before answering any request, with the request itself as the first query."
4. **Binding constraints:** imperative orders, zero rationale sentences, zero exemption clauses (per the directive-not-poetic rule). Facts that must survive somewhere in the shipped surface exactly once: dynamic per-session mount; search-first with the user's request; one snippet over exact returned paths; answer only from returned data; re-search when something is missing; the pending-envelope collect pattern (wait/detail) once prereq-5 text lands. All edits in shipped tool-owned surface only; harness untouched.

## Sequencing
Land BEFORE the exit card's step-4 gated re-measure (^tkrdwb8): the re-measure must run against the final name and final text, or it measures a surface we are about to discard. This card + the two Router cards are then the complete pre-measure set.

## Acceptance Criteria
- [ ] `grep -ri findAPIs Sources Tests` returns only historical prose in comments, if anything — no code identifiers, no model-visible text
- [ ] `sessionInstructions` ≤ 3 sentences; both tool descriptions ≤ ~4 sentences each; arithmetic-exception sentence gone
- [ ] The unconditional sequence (search → runCode over returned paths → answer from returns) survives verbatim in meaning
- [ ] Goldens/renderer tests re-based on the new name via live render, never hand-edited
- [ ] Ungated `swift test` green in both targets
- [ ] Recorded on ^tkrdwb8: this card landed pre-re-measure

## Tests
- [ ] Existing FindAPIsTool/SelectionGrammar/UnknownToolHint/CLI tests updated to the new name — behavior assertions unchanged
- [ ] `swift test` green (both targets)

## Workflow
- Rename mechanically first (compiler-verified), then the text compression as its own commit so the diff is reviewable. #phase-1