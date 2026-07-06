---
comments:
- actor: claude-code
  id: 01kwvxbjexrxt9w9xtm5bnemyq
  text: |-
    Implemented via TDD per the task's Workflow section:
    1. RED: updated all expected fixtures first — `ToolAPIRendererTests.swift`'s `renderCases` table (11 of 12 required-property cases; `optional property` case left untouched) and the 4 `oneSidedBoundsRenderDistinctClauses` assertions (atLeast/atMost/atLeastTags/atMostTags), plus `Goldens/WeatherTool.ts.txt` (`city`) and `Goldens/BuilderSurface.ts.txt` (weather's `city`, echo's `value`, createIssue's `title`, search's `query`). Ran `swift test --filter ToolAPIRendererTests` and confirmed 16 failures, all for the expected reason (missing `(required)` marker), before touching production code.
    2. GREEN: changed `ToolAPIRenderer.paramClause(for:required:)` in `Sources/FoundationModelsMultitool/Surface/ToolAPIRenderer.swift` — the `if !required { clauses.append("(optional)") }` branch became an if/else appending `"(required)"` when `required == true`, symmetric with the existing `"(optional)"` branch. Also updated the doc comment above `paramClause` to describe the new symmetric behavior.
    3. Verified: `swift build` succeeds; `swift test --filter ToolAPIRendererTests` — all 22 tests pass; full `swift test` — 250 tests in 22 suites pass, 0 failures (plus 11 gated evaluation tests correctly skipped, consistent with existing gating in this repo).

    Scoped search confirmed no other test file references `@param args.` lines or `(optional)`/`(required)` text beyond the three files already listed in the task description, so no other goldens needed updates.

    Leaving task in `doing` for review per the implement skill's process.
  timestamp: 2026-07-06T14:29:45.565791+00:00
- actor: claude-code
  id: 01kwvxkegbhs4qr2874mhz5v2m
  text: |-
    really-done verification (fresh, this pass):
    - `swift build`: exit 0.
    - Full `swift test`: 250/250 tests pass across 22 suites, 0 failures (11 gated evaluation tests correctly skipped, per existing repo gating).

    Adversarial double-check verdict: PASS. Diff confirmed minimal and matching the task's stated intent exactly — no unrelated refactors, `(required)` clause correctly positioned last among the parentheticals, doc comment updated, both golden files wired into byte-identical comparison tests and updated consistently, repo-wide search confirmed no other test/golden asserts marker-less required-property `@param` text.

    One informational (non-blocking) finding, logged per really-done's proceed-with-justification option: `plan.md`'s doc-mapping table row and its two worked examples (WeatherTool, librarian-prefix) still show the old marker-less `@param args.city` text and don't mention the new `(required)` marker — stale relative to the actual renderer output. This is design-doc prose only (not consumed by any test), plan.md was not listed in this task's acceptance criteria or Tests section, and plan.md already carried pre-existing staleness unrelated to this change (a documented `default "c"` clause the renderer's own doc comment says is never actually rendered). Proceeding without updating plan.md, consistent with the task's explicit scope (the 4 files named in the description). Flagging in case a follow-up task to refresh plan.md's worked examples is wanted.

    Task is green and ready for review.
  timestamp: 2026-07-06T14:34:03.659478+00:00
position_column: done
position_ordinal: 9d80
title: Add explicit "(required)" marker to ToolAPIRenderer's JSDoc @param clauses
---
## What
`ToolAPIRenderer.paramClause(for:required:)` (`Sources/FoundationModelsMultitool/Surface/ToolAPIRenderer.swift`) composes each tool parameter's `@param args.<name> — <clause>` JSDoc text. Today it appends an explicit `"(optional)"` suffix when a property is *not* required, but appends **nothing** when a property *is* required — required-ness is only ever signaled by the TypeScript type omitting `?` (`args: { city: string }` vs `args?: {...}`) and by the JSDoc clause's *absence* of `(optional)`. There is no explicit `(required)` marker anywhere.

This asymmetry means a reader of the rendered tool description — including the small local model that discovers tools via `findAPIs`/`help()`/`docs(name)` and must decide what fields it has to populate — has to notice a negative (no "(optional)" present) rather than read a positive, explicit signal. Explicit is more robust than implicit, especially for a small model under sampling pressure. Found while diagnosing gated-suite discovery/tool-calling reliability on kanban task `exbtj1n` (FoundationModelsMultitool repo, separate task).

Change `paramClause(for:required:)` to append an explicit `"(required)"` clause (parenthetical, matching the existing `"(optional)"` style and position — appended last, alongside the other type-constraint parentheticals) whenever `required` is `true`, symmetric with the existing `"(optional)"` branch for `required == false`.

This will change the rendered `@param` text for every required property across the codebase, so the following golden/table-driven fixtures must be updated to match the new output:
- `Tests/FoundationModelsMultitoolTests/ToolAPIRendererTests.swift` — the `renderCases` table's `expectedParamLine` values for every required-property case (`"string"`, `"number (float)"`, `"integer, unconstrained"`, `"integer with a range guide"`, `"boolean"`, `"enum / choice of constants"`, `"array<string>, unconstrained"`, `"array<integer> with a count guide"`, `"string with a pattern guide"`, `"nested object"`, `"array of nested object"` — every case except `"optional property"`, which already carries `(optional)` and is unaffected). Also update the `oneSidedBoundsRenderDistinctClauses` test's four standalone assertions: `OneSidedBoundsArgument`'s `atLeast`, `atMost`, `atLeastTags`, and `atMostTags` (`Tests/FoundationModelsMultitoolTests/Fixtures/ToolAPIRendererFixtures.swift`) are all non-optional Swift properties (all required), so all four expected strings need `(required)` appended, e.g. `"@param args.atLeast — at least five. (integer) (minimum 5) (required)"`.
- `Tests/FoundationModelsMultitoolTests/Goldens/WeatherTool.ts.txt` — `@param args.city` (required) needs `(required)` appended; `@param args.units` (optional) stays unchanged.
- `Tests/FoundationModelsMultitoolTests/Goldens/BuilderSurface.ts.txt` — all four rendered tools' required params (`weather`'s `city`, `echo`'s `value`, `createIssue`'s `title`, `search`'s `query`) need `(required)` appended.

## Acceptance Criteria
- [x] `ToolAPIRenderer.paramClause(for:required:)` appends an explicit `"(required)"` clause for every required property, symmetric with the existing `"(optional)"` clause for non-required properties.
- [x] Every rendered tool declaration in the repo (via `swift test`) reflects the new marker — no stale golden fixture left asserting the old, marker-less required-property text.
- [x] `swift build` and full `swift test` remain green with no other regressions.

## Tests
- [x] `Tests/FoundationModelsMultitoolTests/ToolAPIRendererTests.swift` — update `renderCases`' `expectedParamLine` values to append `(required)` on every required-property case, and update `oneSidedBoundsRenderDistinctClauses`'s four assertions (`atLeast`, `atMost`, `atLeastTags`, `atMostTags` — all required) to append `(required)`.
- [x] `Tests/FoundationModelsMultitoolTests/Goldens/WeatherTool.ts.txt` and `Tests/FoundationModelsMultitoolTests/Goldens/BuilderSurface.ts.txt` — update the golden text to include `(required)` on every required param's line; the existing `weatherToolMatchesGoldenFile` test (byte-identical comparison) must pass unchanged in structure, only the golden content updates.
- [x] `swift test --filter ToolAPIRendererTests` passes.
- [x] Full `swift test` passes (no regressions in `HelpDocsTests` or other suites that render/assert tool descriptions).

## Workflow
- Use `/tdd` — update the expected golden/table-driven test values first (watch them fail against the current marker-less output), then implement the `(required)` clause in `paramClause` to make them pass.
