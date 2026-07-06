---
position_column: todo
position_ordinal: '80'
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
- [ ] `ToolAPIRenderer.paramClause(for:required:)` appends an explicit `"(required)"` clause for every required property, symmetric with the existing `"(optional)"` clause for non-required properties.
- [ ] Every rendered tool declaration in the repo (via `swift test`) reflects the new marker — no stale golden fixture left asserting the old, marker-less required-property text.
- [ ] `swift build` and full `swift test` remain green with no other regressions.

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/ToolAPIRendererTests.swift` — update `renderCases`' `expectedParamLine` values to append `(required)` on every required-property case, and update `oneSidedBoundsRenderDistinctClauses`'s four assertions (`atLeast`, `atMost`, `atLeastTags`, `atMostTags` — all required) to append `(required)`.
- [ ] `Tests/FoundationModelsMultitoolTests/Goldens/WeatherTool.ts.txt` and `Tests/FoundationModelsMultitoolTests/Goldens/BuilderSurface.ts.txt` — update the golden text to include `(required)` on every required param's line; the existing `weatherToolMatchesGoldenFile` test (byte-identical comparison) must pass unchanged in structure, only the golden content updates.
- [ ] `swift test --filter ToolAPIRendererTests` passes.
- [ ] Full `swift test` passes (no regressions in `HelpDocsTests` or other suites that render/assert tool descriptions).

## Workflow
- Use `/tdd` — update the expected golden/table-driven test values first (watch them fail against the current marker-less output), then implement the `(required)` clause in `paramClause` to make them pass.
