---
depends_on:
- 01KWQC1N0Q97RKK7J162RTCRHC
position_column: todo
position_ordinal: '8580'
title: Delete Librarian and FoundAPIs; migrate TranscriptAnalyzer to Selection
---
## What
Eliminate the code the registry now owns — including the compile-level migration of the integration test target, which plain `swift test` builds (even though its tests are env-gated), so this task must leave the whole workspace green.

**Deletions:**
- `Sources/FoundationModelsMultitool/Agent/Librarian.swift` — superseded by the registry's `SelectionTier`/`MetadataSearcher` (prefix caching, fork-per-call, capacity fallback; the registry's `SelectionConfig.preamble` defaults to `Librarian.selectionGuidance` verbatim as `.librarianDefault`).
- `Sources/FoundationModelsMultitool/Agent/FoundAPIs.swift` — the `@Generable FoundAPI`/`FoundAPIs` shape is superseded by the registry's public ids-only `Selection` (its doc says so explicitly).
- `Tests/FoundationModelsMultitoolTests/LibrarianTests.swift`, `Tests/FoundationModelsMultitoolTests/Fixtures/LibrarianFixtures.swift`, and `Goldens/LibrarianPrefix.txt` — the behaviors they pinned (prefix assembly, fork-per-call, root caching, capacity fallback, grammar derivation) are owned and tested by the registry.
- **Before deleting `LibrarianFixtures.swift`, relocate its load-bearing fakes into `Fixtures/MultiToolAgentFixtures.swift`:** `CallCounter` (used by `CLIArgumentTests.swift` and `MultiToolAgentTests.swift`), and verify whether `RootSessionRespondCalledDirectlySession` is still used by `GuidedTurnFormatTests.swift` (it is at time of planning — keep it if the rewire task's test migration still needs it, delete otherwise) and whether `RecordingSessionFactory` is needed by `FindAPIToolTests`.

**Migrations (same task, keeps the build green):**
- `Sources/FoundationModelsMultitool/Agent/TranscriptAnalyzer.swift`: replace `foundAPIs(in:slot:)` (decodes `FoundAPIs(GeneratedContent(json:))` from flash-slot `.response` events) with a Selection-decoding equivalent (e.g. `selections(in:slot:) -> [Selection]`) since flash responses now carry `{"ids": [...]}`.
- `Tests/FoundationModelsMultitoolTests/TranscriptAssertionTests.swift` + fixture JSONL transcripts under `Tests/.../Goldens` (e.g. `SearchThenCallTranscript.jsonl` has flash-slot `{"functions":[...]}` events): update to Selection-shaped flash responses.
- **Integration target compile migration** (its gated *execution* is the next task; its *compilation* must be fixed here):
  - `Tests/FoundationModelsMultitoolIntegrationTests/PrefixReuseTests.swift` constructs `Librarian(surface:librarian:)` — rewrite over the internal production searcher factory extracted in the rewire task: build the production `MetadataSearcher<APISurface.Entry>(mode: .selection)`, call `search(intent:limit:)` twice, keep the second-call-not-slower timing assertion.
  - `Tests/FoundationModelsMultitoolIntegrationTests/Support/ScenarioRunner.swift` calls `TranscriptAnalyzer.foundAPIs(...).flatMap(\.functions)` — switch to the Selection-decoding analyzer and assert on selected ids (entry paths); update `SearchThenCallTests.swift`'s `expectedFoundAPINames` accordingly (e.g. `{"tripCities", "weather"}` as paths).
  - `Support/IntegrationGate.swift`: update the stale "drive a `Librarian` directly" comment.
- Clean the stale doc-comment mention of `FoundAPI.init` in `Sources/FoundationModelsMultitool/Agent/AgentTurn.swift`.

## Acceptance Criteria
- [ ] `grep -rn "\bLibrarian(\|: Librarian\|Librarian\.\|FoundAPIs\|FoundAPI(" Sources/ Tests/` returns nothing — no Swift identifier references (types, inits, members) to the deleted types anywhere; prose-only mentions are handled by the docs task.
- [ ] `TranscriptAnalyzer` decodes Selection-shaped flash output; no `FoundAPIs` decoding remains.
- [ ] `CLIArgumentTests` and `GuidedTurnFormatTests` still pass with the relocated fakes.
- [ ] `swift build` and full `swift test` green — including compilation of `FoundationModelsMultitoolIntegrationTests`.

## Tests
- [ ] Updated `TranscriptAssertionTests` decode Selection ids from the updated fixture JSONL transcripts.
- [ ] `swift test` — full suite green after the deletions (integration tests compile; their execution stays env-gated).

## Workflow
- Use `/tdd` — update the failing transcript-assertion tests first, then migrate the analyzer.