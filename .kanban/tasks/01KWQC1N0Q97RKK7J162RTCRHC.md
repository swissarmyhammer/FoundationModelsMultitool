---
depends_on:
- 01KWQCK35ZRQGCSWX193Q0AR38
- 01KWQC0DCNNCB2SJ3KNP44M84D
- 01KWQC0TWTN5M1JX0150BV3XSE
position_column: todo
position_ordinal: '8480'
title: Rewire findAPIs over MetadataSearcher (.selection mode)
---
## What
Replace the `Librarian` actor with the registry's selection tier. The registry's `SelectionTier` already generalizes Librarian's exact mechanics (cached root session, `fork()` per call, capacity fallback) and improves on them: ids-only output under an id-enum xgrammar (the model is structurally incapable of inventing a function), ranked-retrieval top-M over budget (vs. Librarian's crude lexical pre-filter), and `.retrievalCut`/`.unknownSelectedId` diagnostics. The `idEnumGrammar(ids:)` helper already exists from the preceding task.

1. **Rewrite `Sources/FoundationModelsMultitool/Agent/FindAPITool.swift`** — hold a `MetadataSearcher<APISurface.Entry>` (plus the catalog entry count as the search limit, so nothing the model legitimately selected is truncated). `dispatch(task:)` calls `searcher.search(intent: task, limit:)` and formats each match. **Formatting must preserve namespace qualification for grouped tools:** `ToolDescriptor` fields are always unqualified (`declaration` is the bare `declare function weather(...)` line; `path` carries the namespace — see `APISurface.swift`'s Entry docs). So splice `match.item.block` (the `// tools.<path>` banner + verbatim `descriptor.source`) followed by `Example: \(match.item.descriptor.example)` — never the bare `declaration`/`doc` alone. Keep the existing framing: `findAPIs("<task>") found:` header, blocks separated by blank lines, and the `findAPIs("<task>") found no matching functions.` empty case.
2. **Rewire `Sources/FoundationModelsMultitool/Agent/MultiToolAgent.swift`**:
   - Production init: replace `Librarian(surface: registry.surface, librarian: librarian)` with: derive `idEnumGrammar(ids: registry.surface.entries.map(\.path))`; build `SelectionConfig(model: { RoutedAgentSession(session: librarian.makeGuidedSession(grammar, instructions: $0)) })`; construct `MetadataSearcher(items: registry.surface.entries, mode: .selection, selection: config)`; wrap in `FindAPITool`. Signature stays `librarian: RoutedLLM? = nil` — callers (CLI) unchanged. Extract this searcher construction into an internal factory so the gated integration test (later task) can drive the identical production wiring.
   - Internal test-facing init: replace `librarian: Librarian?` with `findAPISearcher: MetadataSearcher<APISurface.Entry>?` (tests build one with a scripted `SelectionConfig.model` factory).
3. **Migrate the affected unit tests in the same task — the suite must end green:**
   - `Tests/FoundationModelsMultitoolTests/LibrarianTests.swift` calls `FindAPITool(librarian:)` in its splice-through and empty-result tests: move those two behaviors into a new `FindAPIToolTests.swift` driven by a scripted searcher/`SelectionConfig`; the remaining `LibrarianTests` content (prefix golden, lexical filter, grammar derivation, fork-count tests against `Librarian` itself) still compiles because `Librarian.swift` is deleted only in the next task.
   - `MultiToolAgentTests.swift`, `GuidedTurnFormatTests.swift`, `Fixtures/MultiToolAgentFixtures.swift`: scripted flash sessions now return `{"ids": ["<path>", ...]}` Selection JSON instead of canned `FoundAPIs` JSON; assert the verbatim `block`-based splice lands in the transcript. Drop unit assertions that re-test the registry's own internals (fork-count, root-cached-once) — those live in the registry's suite; keep splice-through and empty-result formatting assertions.

## Acceptance Criteria
- [ ] `MultiToolAgent` production init no longer references `Librarian`; `findAPIs` dispatch flows through `MetadataSearcher.search(intent:limit:)` in `.selection` mode.
- [ ] `FindAPITool` output splices `match.item.block` (including the `// tools.<path>` banner) plus the example, verbatim; a grouped-tool test proves the qualified path appears in the output; empty selection yields the "found no matching functions." message.
- [ ] Selection sessions are grammar-constrained to exactly the surface's entry paths (unit test inspects the grammar's id enum).
- [ ] `swift build` and full `swift test` green at task completion (including still-present LibrarianTests).

## Tests
- [ ] New `FindAPIToolTests.swift`: scripted selection → verbatim `block`-based formatted output (one standalone and one grouped entry); empty ids → no-match message.
- [ ] Updated `MultiToolAgentTests`/`GuidedTurnFormatTests`: agent loop end-to-end with scripted `{"ids": [...]}` flash responses.
- [ ] `swift test` — full suite green.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.