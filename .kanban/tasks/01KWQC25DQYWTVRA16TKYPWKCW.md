---
comments:
- actor: wballard
  id: 01kwqjwdfrryyjyhb3gy46mgzz
  text: |-
    Implementation complete. Changes:

    - Deleted Sources/FoundationModelsMultitool/Agent/Librarian.swift and FoundAPIs.swift.
    - Deleted Tests/FoundationModelsMultitoolTests/LibrarianTests.swift, Fixtures/LibrarianFixtures.swift, Goldens/LibrarianPrefix.txt.
    - Relocated still-needed shared fakes (CallCounter, TripCitiesTool/TripCitiesOutput, RootSessionRespondCalledDirectlySession/Error) from LibrarianFixtures.swift into Fixtures/MultiToolAgentFixtures.swift, since CLIArgumentTests, GuidedTurnFormatTests, MultiToolAgentTests, and FindAPIToolTests still depend on them. RecordingSessionFactory was NOT relocated — nothing outside the deleted LibrarianTests.swift used it.
    - TranscriptAnalyzer.swift: renamed `foundAPIs(in:slot:) -> [FoundAPIs]` to `selections(in:slot:) -> [Selection]`, decoding via `Selection(GeneratedContent(json:))`.
    - TranscriptAssertionTests.swift + Goldens/SearchThenCallTranscript.jsonl updated to the ids-only Selection shape (`{"ids":["tripCities","weather"]}` replacing `{"functions":[...]}`).
    - Integration test target (compiles, execution stays env-gated): PrefixReuseTests.swift now drives `MultiToolAgent.makeFindAPISearcher(registry:librarian:)` + `MetadataSearcher.search(intent:limit:)` instead of constructing `Librarian` directly; ScenarioRunner.swift's `expectedFoundAPINames` assertion decodes via `TranscriptAnalyzer.selections(...).flatMap(\.ids)`; IntegrationGate.swift's stale "drive a Librarian directly" doc comment fixed.
    - AgentTurn.swift's doc no longer cites deleted `FoundAPI.init` (now cites `ToolDescriptor.init`); APISurface+SearchableMetadata.swift's doc no longer cites deleted `Librarian.assemblePrefix`.

    Verification: `swift build`, `swift build --build-tests`, and `swift test` all green. Full test run: 250 tests in FoundationModelsMultitoolTests, only 1 failure — HardeningTests.readmeInjectedGlobalsListMatchesRuntime, the known pre-existing failure tracked separately (short_id 1pn8764), not introduced by this change. Gated FoundationModelsMultitoolIntegrationTests target compiles cleanly; its 11 tests skip cleanly (MULTITOOL_INTEGRATION unset).

    `grep -rn "\bLibrarian(\|: Librarian\|Librarian\.\|FoundAPIs\|FoundAPI(" Sources/ Tests/` returns only prose doc-comment mentions (explanatory "formerly X" references in TranscriptAnalyzer.swift and MultiToolAgentFixtures.swift), no live Swift identifier references — matches the acceptance criterion's carve-out for prose handled by the docs task.

    double-check adversarial review dispatched (async); will report its verdict once it returns.
  timestamp: 2026-07-04T22:09:45.464428+00:00
- actor: wballard
  id: 01kwqk1fs6x3qzkxk4pa4wbcg9
  text: |-
    Adversarial double-check (via really-done) returned PASS, no findings:
    - Selection/MetadataSearcher API usage verified against the actual checked-out FoundationModelsMetadataRegistry package source.
    - No dangling references to Librarian/FoundAPIs/FoundAPI remain outside historical doc-comment prose; no leftover callers of the old foundAPIs(in:slot:) name.
    - Relocated fixtures (CallCounter, TripCitiesTool/TripCitiesOutput, RootSessionRespondCalledDirectlySession/Error) are byte-for-byte consistent with their originals and confirmed used by CLIArgumentTests, MultiToolAgentTests, GuidedTurnFormatTests, FindAPIToolTests, APISurfaceSearchableMetadataTests, SelectionGrammarTests; RecordingSessionFactory correctly has zero remaining references.
    - Golden JSONL fixture and its consuming assertions agree.
    - Independently reran swift build / swift build --build-tests / swift test: 250 tests, exactly 1 failure (the known pre-existing HardeningTests README/runtime-globals sync check, short_id 1pn8764), matching the reported result exactly.

    Task is green and complete. Leaving in `doing` per the implement skill's process — /review will pull it into review.
  timestamp: 2026-07-04T22:12:31.654376+00:00
depends_on:
- 01KWQC1N0Q97RKK7J162RTCRHC
position_column: doing
position_ordinal: '80'
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