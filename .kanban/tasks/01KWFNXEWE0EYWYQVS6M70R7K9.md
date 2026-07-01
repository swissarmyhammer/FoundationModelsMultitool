---
depends_on:
- 01KWFNVX4RFZZKEKY4C08F8V0Y
- 01KWFNWJECBNSZCANVMNTR3Z8J
- 01KWFP7Q1REW7YKJ6DZJMB9F18
position_column: todo
position_ordinal: 8b80
title: 'M6.5a: Gated integration test target + four sample MultiTools'
---
## What
Per plan.md M6.5 + Testing strategy "Integration tests": the real-model suite, modeled on Router's own gated `IntegrationTests` target.
- New test target `FoundationModelsMultitoolIntegrationTests` in `Package.swift`, opt-in via env var (e.g. `MULTITOOL_INTEGRATION=1`), never in default CI. It links `FoundationModelsRouter` plus the Hub/tokenizer products the Router's integration target uses (mirror `../FoundationModelsRouter/Package.swift` `hubProducts`).
- A `ProfileDefinition` of deliberately small tool-calling-capable instruct models (standard + flash + embedding candidates; pick refs at implementation time, preferring what Router's own integration suite already downloads).
- Four scenario fixtures (each a small tool set + prompt + expected trace), per plan.md: (1) single-call `weather`; (2) compose/chain `tripCities`→`weather`→warmest; (3) discovery under ~20 distractor tools; (4) repair from a deliberately trip-prone tool. Run each under BOTH turn formats (`.tolerantParse` from M4b, `.guided` from M4c) — this is where the plan's empirical turn-format decision is settled and recorded.
- **Librarian prefix-reuse pin (plan Finding #6 / Remaining pins):** a gated measurement asserts the librarian's second `findAPIs` call does not re-prefill the surface prefix — compared via prefill latency and/or prompt token evidence from the Router JSONL transcript — OR confirms the `fork()` fallback is engaged and documents which mechanism holds.
- Trace assertions read the Router JSONL transcript (`RecordingLevel.full`): findAPIs before runCode, librarian returned the expected minimal set, snippet invoked exactly the expected `tools.*`, repair within N turns.
- Skip cleanly (Swift Testing `.enabled(if:)` + a skip on `GenerationError.notWiredForLiveInference`) until the Router's live-inference milestone lands.

## Acceptance Criteria
- [ ] `swift test` WITHOUT the env var: integration suite reports skipped, zero downloads
- [ ] With the env var on capable hardware + live Router: all four scenarios pass their trace assertions under at least one turn format, and the per-format results are recorded (test attachment or log) to settle the M4b/M4c default
- [ ] Prefix-reuse measurement passes: second findAPIs call shows no full re-prefill, or the fork() fallback is confirmed engaged (assertion, not observation)
- [ ] Transcript-parsing helpers are themselves unit-tested against checked-in fixture JSONL (runs in normal CI)
- [ ] Router live-path unavailable → suite skips with the typed reason, not failure

## Tests
- [ ] `Tests/FoundationModelsMultitoolIntegrationTests/SearchThenCallTests.swift` — the four gated scenarios × two turn formats
- [ ] `Tests/FoundationModelsMultitoolIntegrationTests/PrefixReuseTests.swift` — the gated prefix-reuse measurement
- [ ] `Tests/FoundationModelsMultitoolTests/TranscriptAssertionTests.swift` — ungated unit tests of the JSONL trace parser on fixtures
- [ ] `swift test --filter TranscriptAssertionTests` → passes in normal CI

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.