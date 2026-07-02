---
comments:
- actor: wballard
  id: 01kwhzn6qkde1pef65z6ascg86
  text: |-
    Implemented via TDD. Wrote Tests/FoundationModelsMultitoolTests/HelpDocsTests.swift first (6 tests reusing WeatherTool/GithubCreateIssueTool fixtures), confirmed RED (all 6 failed with JSON decode errors / false, since help/docs weren't defined yet — ReferenceError caught and rendered as repairable error text by the existing ResultRenderer path). Then implemented in Sources/FoundationModelsMultitool/MultiTool.swift: added a "help()/docs() globals" section — `makeHelpDocsHostFunctions(for:)` builds two more HostFunctions ("help", "docs") appended to the existing `hostFunctions` array in init, installed as flat globals alongside tools.* (not namespaced). help() returns `registry.surface.entries.map(\.path)` (already "group.name" for grouped entries — no extra logic needed, path already encodes Resolved #5's layout). docs(name) does exact-match lookup against `surface.entries` and returns `entry.block` verbatim (reusing APISurface.Entry.block per the task instructions, no re-rendering). Unknown name -> "Unknown tool "X". Did you mean: ...?" built from a hand-rolled Levenshtein-distance nearest-match ranker (nearestMatches/levenshteinDistance, top 3, simple DP, no library). Non-string argument -> fixed usage-hint string, never crashes.

    Escaping note: confirmed no splice-into-source risk here (unlike M2's ToolAPIRenderer) — help()/docs() return values cross back into JS via the existing InterpreterValue -> JSON.parse round-trip (JSCInterpreter.jsValue(from:in:)), i.e. they're returned as JS *data* through the same host-function bridge every tools.* call already uses, not interpolated into generated JS source text. Documented this reasoning in the new code's doc comments.

    Verification: swift build clean; swift test full suite 145/145 passing (up from 139/139 baseline, all 6 new HelpDocsTests green, nothing else broken). Adversarial double-check agent dispatched to review before handoff.
  timestamp: 2026-07-02T17:57:34.067606+00:00
depends_on:
- 01KWFNVC3SA55SBZMCCWW6994C
position_column: doing
position_ordinal: '80'
title: 'M7: In-snippet help() / docs() globals'
---
## What
Per plan.md M7: in-language introspection backed by the same `APISurface` (one source of truth with the librarian prefix and findAPIs).
- Extend the interpreter installation in `MultiTool.swift`: inject `help()` → array of available function names (grouped layout shown per plan Resolved #5), and `docs(name)` → that tool's full rendered block (signature + doc + example); unknown name → helpful error listing close matches.
- These are the only extra globals; the deny-by-default sandbox is otherwise unchanged.

## Acceptance Criteria
- [x] `runCode("return help()")` returns all names incl. `group.name` entries
- [x] `runCode("return docs('weather')")` returns the exact rendered block from the surface
- [x] `docs('nope')` returns an error message naming near-matches, not a crash
- [x] Sandbox check: no other new globals are reachable

## Tests
- [x] `Tests/FoundationModelsMultitoolTests/HelpDocsTests.swift` — the four criteria above against a fixture surface
- [x] `swift test --filter HelpDocsTests` → passes

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Implementation notes (2026-07-02)

Implemented in `Sources/FoundationModelsMultitool/MultiTool.swift`: a new "help()/docs() globals" section adds `makeHelpDocsHostFunctions(for:)`, which builds two more `HostFunction`s ("help", "docs") appended into the existing `hostFunctions` array in `MultiTool.init`, installed as flat globals alongside `tools.*` (not namespaced). `help()` returns `registry.surface.entries.map(\.path)` — the path already encodes Resolved #5's grouped layout (`"github.createIssue"`), no extra logic needed. `docs(name)` exact-matches against `surface.entries` and returns `entry.block` verbatim (`APISurface.Entry.block`, reused per the task's explicit instruction — no re-rendering). An unknown name returns `"Unknown tool \"X\". Did you mean: ...?"` built from a hand-rolled Levenshtein-distance nearest-match ranker (`nearestMatches`/`levenshteinDistance`, simple two-row DP, top 3 — no fuzzy-matching library, per the task's own guidance). A missing/non-string argument returns a fixed usage-hint string rather than crashing.

Escaping: confirmed and documented in the code that `help()`/`docs()` return values cross back into JS via the *existing* `InterpreterValue` → `JSON.parse` round-trip (`JSCInterpreter.jsValue(from:in:)`) — i.e. real JS *data* through the same host-function bridge every `tools.*` call already uses, not interpolated into generated JS source text. So, unlike M2's `ToolAPIRenderer` splice sites, no additional escaping treatment is needed here; a schema-derived tool name containing a quote or newline just becomes an ordinary JS string value.

Tests: `Tests/FoundationModelsMultitoolTests/HelpDocsTests.swift` (new), 7 tests, reusing `WeatherTool`/`GithubCreateIssueTool` fixtures rather than authoring bespoke ones. TDD: wrote tests first, confirmed RED (6 failures — `help`/`docs` undefined, caught as a JS `ReferenceError` and rendered through the existing repairable-error path), then implemented to GREEN.

Adversarial double-check (via `double-check` agent) ran against the diff: found one legitimate gap — no regression test for `docs()` called with a missing/non-string argument, a documented crash-prevention branch. Fixed by adding `docsWithMissingOrNonStringArgumentReturnsUsageHint`. Re-verified: `swift build` clean, `swift test` 146/146 passing (up from 139/139 baseline). A minor/optional suggestion (strengthen the sandbox test to positively enumerate `Object.getOwnPropertyNames` rather than spot-check three known globals) was left as-is — explicitly called "not a blocker," and matches this repo's existing sandbox-test style.

Left in `doing` for `/review` per the implement skill's process.