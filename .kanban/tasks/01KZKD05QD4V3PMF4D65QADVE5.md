---
assignees:
- claude-code
position_column: todo
position_ordinal: '8380'
title: '[Multitool] Rename findAPIs → searchTools and cut the prompt surface to code-mode industry weight'
---
HUMAN-DIRECTED (2026-08-09). Three changes, one card: the discovery tool's name, the in-sandbox catalog globals' names and shapes, and the size of the prompt surface.

## Why (researched, not guessed)

**The name.** `findAPIs` is our invention; the field has converged on "search". Anthropic's code-execution-with-MCP engineering post names the discovery tool `search_tools`. Cloudflare Code Mode's sandbox global is `codemode.search(query)` (paired with `codemode.describe(target)`). Our pairing should read `searchTools` / `runCode` — two camelCase verb-first siblings. "findAPIs" also mis-describes what comes back: it returns tool-functions, not APIs.

**The catalog globals.** The human has also seen the `listTools(glob?)` → name+description / `describeTool(name)` → full detail shape in the field. We ALREADY ship that pair, half-baked, as sandbox globals: `help()` returns bare paths (no descriptions, no filter; MultiTool.swift:1034) and `docs(name)` returns the full `APISurface.Entry.block`. Align ours to the industry shape and names. They stay IN-SANDBOX — that is where Cloudflare puts search/describe too — and the mounted surface stays exactly two tools (21effa4 "mount the two tools and nothing else"; the instruction-footprint budget is the reason).

**The length.** Cloudflare's outer tool description is approximately one sentence — "write a JavaScript async arrow function" plus the connector namespace list. The typed declarations returned BY discovery carry the teaching. Our `sessionInstructions` is ~8 paragraphs and the descriptions repeat each other. The human's verdict: "this is all too wordy." Specific cut ordered: the pure-arithmetic exception sentence — delete it entirely; no exemption clauses that give the model a reason to skip search.

## What

1. **Rename the wire name `findAPIs` → `searchTools`** everywhere the model can see it: the tool's `name`, both tool descriptions' references, `sessionInstructions`, sandbox catalog-global text, `UnknownToolHint` text if it names the tool, sample snippets, worked examples, CLI output. Rename the Swift types to match (`FindAPIsTool` → `SearchToolsTool`, etc.) — no legacy alias, no deprecation shim; nothing outside this org consumes it yet.
2. **Rename and finish the sandbox catalog globals** (JS convention, matching the field):
   - `help()` → `listTools(glob?)` — returns `{ path, description }` pairs (one-line description from the same `APISurface.Entry` source; today it returns bare paths). Optional glob filters by path (`fnmatch`-style, e.g. `listTools("get*")`); no argument lists everything. Output stays under the same render cap as everything else.
   - `docs(name)` → `describeTool(name)` — behavior unchanged: the exact `APISurface.Entry.block` for that path; the globals-page topic keyword keeps working.
   - Update the runCode description's mention (currently "help()/docs(name)"), the sandbox docs page, `HardeningTests`' pinned global set, and the README list. One generator, one source of truth — both globals keep reading `registry.surface`.
3. **Compress the prompt surface hard.** Target: `sessionInstructions` ≤ 3 sentences; each tool description ≤ ~4 sentences. Keep the measured unconditional sequence — it is the one text intervention with a clean result (over-refusal 3/20→0/20, answered-without-calling 2/20→0/20): search first with the user's request, one runCode over the exact returned paths, answer only from what returned. Delete: the arithmetic exception, the "narrow follow-up searches come after" elaboration, the repeated "including the user's own data" claims (say it once), and any sentence that restates another surface's sentence. The typed signatures + runnable examples returned by searchTools remain the real teacher.
4. **Draft to start from** (edit freely; constraints below are binding):
   - sessionInstructions: "This session's functions are mounted dynamically — searchTools is the only way to see them. For every request: call searchTools with the request itself, write one runCode snippet calling the exact tools.* paths it returns, and answer only from what the snippet returns. Search again for anything still missing; never guess a function name and never ask the user for data the tools can fetch."
   - searchTools description: "Describe the task in plain language; returns the relevant tool-functions with typed signatures and runnable examples. Call it before answering any request, with the request itself as the first query."
5. **Binding constraints:** imperative orders, zero rationale sentences, zero exemption clauses (per the directive-not-poetic rule). Facts that must survive somewhere in the shipped surface exactly once: dynamic per-session mount; search-first with the user's request; one snippet over exact returned paths; answer only from returned data; re-search when something is missing; in-snippet catalog reads via listTools/describeTool; the pending-envelope collect pattern (wait/detail) once prereq-5 text lands. All edits in shipped tool-owned surface only; harness untouched. The mounted surface stays exactly two tools — listTools/describeTool are sandbox globals, NOT session tools.

## Sequencing
Land BEFORE the exit card's step-4 gated re-measure (^tkrdwb8): the re-measure must run against the final names and final text, or it measures a surface we are about to discard. This card + the two Router cards are then the complete pre-measure set.

## Acceptance Criteria
- [ ] `grep -ri findAPIs Sources Tests` returns only historical prose in comments, if anything — no code identifiers, no model-visible text
- [ ] `help(`/`docs(` gone the same way: sandbox installs `listTools`/`describeTool`; `listTools()` returns path+description pairs; `listTools("glob*")` filters; `describeTool(name)` returns the entry block
- [ ] `sessionInstructions` ≤ 3 sentences; both tool descriptions ≤ ~4 sentences each; arithmetic-exception sentence gone
- [ ] The unconditional sequence (search → runCode over returned paths → answer from returns) survives verbatim in meaning
- [ ] `HardeningTests`' pinned global set and the README list updated to the new global names — no extra globals appear
- [ ] Goldens/renderer tests re-based on the new names via live render, never hand-edited
- [ ] Ungated `swift test` green in both targets
- [ ] Recorded on ^tkrdwb8: this card landed pre-re-measure

## Tests
- [ ] Existing FindAPIsTool/SelectionGrammar/UnknownToolHint/CLI tests updated to the new name — behavior assertions unchanged
- [ ] New/updated sandbox tests: listTools() unfiltered, listTools(glob) filtered, describeTool(known) exact block, describeTool(unknown) repairable error
- [ ] `swift test` green (both targets)

## Workflow
- Rename mechanically first (compiler-verified), then listTools/describeTool shape work, then the text compression — three reviewable commits. #phase-1