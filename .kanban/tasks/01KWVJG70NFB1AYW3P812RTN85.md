---
position_column: todo
position_ordinal: '8280'
title: Qualify grouped tools' rendered example call path in findAPIs/docs()/help() results
---
## What
For a grouped tool (added via `MultiTool.Builder.addGroup(named:_:)`), the runnable example text the model actually sees is **wrong** — it shows the bare, unqualified call (`tools.search(...)`) instead of the real, fully-qualified call path (`tools.github.search(...)`) needed to invoke it. The correct qualified path currently appears *only* as a `//` comment banner immediately above the (wrong) example — and a model cannot be expected to infer "prepend the group name from a nearby comment" on its own. Per user: "the model is never gonna figure to do tools.github... what I expected was a top level search function that searches all tools and tells you enough in the search results to be properly qualified." The fix belongs in what the search results/docs *say*, not in the model's inference.

Root cause: `ToolAPIRenderer.render` (`Sources/FoundationModelsMultitool/Surface/ToolAPIRenderer.swift`) renders each tool's `ToolDescriptor` — `declaration`/`doc`/`example`/`source` — namespace-agnostically (deliberately: one render call per tool, reused for the runtime binding regardless of where it ends up namespaced). `APISurface.Entry` (`Sources/FoundationModelsMultitool/Surface/APISurface.swift`) layers the real, fully-qualified `path` (`"<group>.<name>"` for a grouped tool) on top, but only as a `// tools.<path>` banner line prepended to `descriptor.source` — `descriptor.source`'s own embedded JSDoc `@example` line, and the standalone `descriptor.example` field, both still read `tools.<name>(...)` (bare), since they were rendered before the entry's namespace was known. This mismatch is visible today in `Tests/FoundationModelsMultitoolTests/Goldens/BuilderSurface.ts.txt`: the `github.createIssue`/`github.search` entries' banners correctly say `// tools.github.createIssue` / `// tools.github.search`, but their `@example` lines say `tools.createIssue(...)` / `tools.search(...)`.

This affects every consumer of `Entry.block`/`APISurface.source`, not just `findAPIs`:
- `FindAPITool.format` (`Sources/FoundationModelsMultitool/Agent/FindAPITool.swift`) splices `match.item.block` *and* separately appends `"Example: \(match.item.descriptor.example)"` — both wrong for a grouped tool.
- `MultiTool.swift`'s `docs(name)` returns `entry.block` directly — same embedded wrong `@example`.
- `APISurface.source` (every entry's `.block`, joined) backs the registry-backed selection tier's own instruction prefix — so even the *selection* model reads the wrong example when deciding what's relevant.

Fix `APISurface.Entry` so its rendered text always shows the fully-qualified call path in every place an example/call is shown — not just the banner. Since `descriptor.example`/the embedded `@example` line are always generated as exactly `"tools.\(descriptor.name)(...)"` (per `ToolAPIRenderer.render`'s `exampleCall` construction — `descriptor.name` is validated as a legal TS identifier, so this prefix is unambiguous and safe to target), the qualification can be done at the `Entry` level with a targeted substitution of the `"tools.\(descriptor.name)("` prefix for `"tools.\(path)("` — a no-op for a standalone entry (`path == descriptor.name`), and correctly qualifying it for a grouped entry — applied everywhere that prefix appears in `descriptor.source`/`block` (the embedded JSDoc `@example`) and in `descriptor.example` itself (used by `FindAPITool.format`'s separate trailer line).

## Acceptance Criteria
- [ ] `APISurface.Entry.block` (and therefore `APISurface.source`, `docs(name)`'s result, and the registry-backed selection tier's instruction prefix) shows the fully-qualified `tools.<path>(...)` call in its embedded `@example` line for a grouped tool — never the bare `tools.<name>(...)`.
- [ ] `FindAPITool.format`'s separate `"Example: ..."` trailer also shows the qualified call for a grouped tool (either by deriving it the same way, or by removing the now-redundant trailer if `block`'s own embedded example already suffices — pick whichever avoids showing two different, possibly-conflicting example strings in the same feedback text).
- [ ] A standalone tool's rendered example is unaffected (`path == descriptor.name`, so the substitution is a no-op) — no behavior change for the non-grouped case.
- [ ] `swift build` and full `swift test` remain green.

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/FindAPIToolTests.swift`'s `groupedSelectionSplicesQualifiedPath` — currently only asserts the `// tools.github.createIssue` banner is present; add an assertion that the feedback also contains the qualified example call `tools.github.createIssue(` and does **not** contain the bare, wrong `tools.createIssue(` as a call (as opposed to substring-matching inside the correct qualified form).
- [ ] `Tests/FoundationModelsMultitoolTests/Goldens/BuilderSurface.ts.txt` — update the golden text so `github.createIssue`/`github.search`'s `@example` lines show `tools.github.createIssue(...)`/`tools.github.search(...)`; the existing `BuilderSurfaceTests.fixtureSetMatchesGoldenFile` test must still pass against the updated golden.
- [ ] `swift test --filter FindAPIToolTests` and `swift test --filter BuilderSurfaceTests` pass.
- [ ] Full `swift test` passes with no regressions (check `HelpDocsTests`/`docs(name)`-related tests too, since they also read `entry.block`).

## Workflow
- Use `/tdd` — first extend `groupedSelectionSplicesQualifiedPath` (or add a new test) asserting the qualified example, watch it fail against the current unqualified output, then implement the `Entry`-level qualification to make it pass, then update the `BuilderSurface.ts.txt` golden to match.
