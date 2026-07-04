---
depends_on:
- 01KWQC25DQYWTVRA16TKYPWKCW
position_column: todo
position_ordinal: '8680'
title: Run and fix the gated integration suite on real hardware
---
## What
The compile-level migration of `Tests/FoundationModelsMultitoolIntegrationTests` (PrefixReuseTests over the production `MetadataSearcher`, ScenarioRunner/SearchThenCallTests over Selection ids) lands in the preceding cleanup task. This task is the gated *execution* pass on GPU hardware: run the migrated suite against real models and fix what only a live run can surface.

- Run `MULTITOOL_INTEGRATION=1 swift test --filter FoundationModelsMultitoolIntegrationTests` on capable hardware.
- Verify and, if needed, fix:
  - **Prefix reuse still holds end-to-end through this package's wiring:** `PrefixReuseTests`' second `search(intent:limit:)` call (fork-inherited prefix) is not slower than the first (cold prefill) — the empirical plan.md Finding #6 pin, now exercised through the registry's cached-root + fork-per-call path.
  - **Selection accuracy:** scenario 3 selects `tripCities` + `weather` among ~20 distractors, now as grammar-constrained ids rather than generated `FoundAPIs` — assert via the Selection-decoding `TranscriptAnalyzer`.
  - Scenario semantics unchanged: findAPIs-precedes-runCode, exact invoked `tools.*` paths, repair-turn bounds.
- Real-model behavior may need tuning (e.g. the selection preamble via `SelectionConfig.preamble`, or the search `limit`); make such adjustments here with the gated suite as the arbiter.

## Acceptance Criteria
- [ ] `MULTITOOL_INTEGRATION=1 swift test --filter FoundationModelsMultitoolIntegrationTests` passes on GPU hardware.
- [ ] Plain (ungated) `swift test` remains green.
- [ ] No `Librarian`/`FoundAPI` identifier references exist under `Tests/FoundationModelsMultitoolIntegrationTests` (carried over from the cleanup task; re-verified here).

## Tests
- [ ] The gated suite itself: `MULTITOOL_INTEGRATION=1 swift test --filter FoundationModelsMultitoolIntegrationTests` — all scenarios pass.
- [ ] `swift test` (ungated) — full suite green.

## Workflow
- Use `/tdd` — the gated suite is the failing-first signal; fix until green.