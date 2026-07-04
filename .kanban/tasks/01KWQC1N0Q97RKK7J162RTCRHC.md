---
comments:
- actor: wballard
  id: 01kwqhq6je5q4n2bmvrexvwnsn
  text: |-
    Implementation landed:

    - `Sources/FoundationModelsMultitool/Agent/FindAPITool.swift` rewritten to hold a `MetadataSearcher<APISurface.Entry>` + entry-count `limit`, dispatching via `searcher.search(intent:limit:)` and formatting each `Match` by splicing `match.item.block` (verbatim, banner included) + `Example: \(match.item.descriptor.example)`.
    - `Sources/FoundationModelsMultitool/Agent/MultiToolAgent.swift`: production init now builds the searcher via new `static func makeFindAPISearcher(registry:librarian:)` (derives `idEnumGrammar(ids: registry.surface.entries.map(\.path))`, wires `SelectionConfig(model:)` to `RoutedAgentSession(session: librarian.makeGuidedSession(grammar, instructions:))`, constructs `MetadataSearcher(items:mode: .selection, selection:)`); internal test-facing init's `librarian: Librarian?` param replaced with `findAPISearcher: MetadataSearcher<APISurface.Entry>?`. `Librarian.swift` untouched (deletion is the next task).
    - New `Tests/FoundationModelsMultitoolTests/FindAPIToolTests.swift`: scripted `.selection` searcher proving verbatim splice for a standalone tool, a grouped tool (qualified `tools.github.createIssue` banner), and empty-selection no-match message.
    - `LibrarianTests.swift`: removed the two `FindAPITool(librarian:)`-based tests (migrated to FindAPIToolTests.swift); golden-prefix/fork-count/lexical-filter/grammar-derivation tests against `Librarian` itself kept as-is.
    - `MultiToolAgentTests.swift`/`GuidedTurnFormatTests.swift`/`Fixtures/MultiToolAgentFixtures.swift`: findAPIs scenarios now build a `.selection`-mode `MetadataSearcher` (new `makeScriptedFindAPISearcher` helper) instead of a `Librarian`, scripted with `{"ids":[...]}` Selection JSON; content assertions updated to match the real `ToolAPIRenderer` output instead of canned `FoundAPIs` JSON text.
    - `SelectionGrammarTests.swift`: added a test proving `idEnumGrammar(ids: registry.surface.entries.map(\.path))` (matching `makeFindAPISearcher`'s own derivation) constrains to the surface's real entry paths incl. a grouped tool's qualified path.

    Verification: `swift build`, `swift build --build-tests`, and `swift test` all run clean. Full suite: 255/256 pass; the sole failure is the pre-existing, unrelated `HardeningTests.readmeInjectedGlobalsListMatchesRuntime` (tracked separately as task 1pn8764) — confirmed not a regression from this change.

    Adversarial double-check dispatched for sign-off; will record its verdict once returned.
  timestamp: 2026-07-04T21:49:25.966669+00:00
- actor: wballard
  id: 01kwqhwchtf5x5vvjsyth4ak73
  text: |-
    Adversarial double-check (independent agent) returned VERDICT: PASS. It independently confirmed:
    - FindAPITool.swift/MultiToolAgent.swift match spec exactly (searcher+limit, makeFindAPISearcher factory, .selection mode, verbatim block+example splice, no-match message).
    - Librarian.swift has zero diff — no scope creep, as required (its deletion is the next task).
    - Test migration genuinely moved (not dropped) coverage: the two FindAPITool(librarian:) tests now live in FindAPIToolTests.swift with equal/greater coverage (standalone + grouped qualified-path + empty-selection).
    - No dangling fixture references after removing cannedEmptyFoundAPIsJSON.
    - Independently re-ran swift build / swift build --build-tests / swift test: 256 tests, 1 failure — the same pre-existing, unrelated HardeningTests README "Injected globals" failure (task 1pn8764), stemming from the prior README-rewrite commit e366c62.

    Task is green per /implement's gate. Leaving in `doing` for `/review` to pick up next, per the implement skill's process (implement never moves a task to review itself).
  timestamp: 2026-07-04T21:52:15.930256+00:00
depends_on:
- 01KWQCK35ZRQGCSWX193Q0AR38
- 01KWQC0DCNNCB2SJ3KNP44M84D
- 01KWQC0TWTN5M1JX0150BV3XSE
position_column: done
position_ordinal: '9980'
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