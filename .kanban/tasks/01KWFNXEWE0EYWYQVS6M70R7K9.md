---
comments:
- actor: wballard
  id: 01kwkz35z16tjdkbce07btyhyx
  text: |
    Implemented via TDD.

    ## What was built

    **Package.swift**: added the gated `FoundationModelsMultitoolIntegrationTests` test target. It links `FoundationModelsRouter` plus (beyond the literal "hubProducts" shorthand in the card) `MLXLMCommon`/`MLXHuggingFace` (from a new direct `mlx-swift-lm` package dependency) and `HuggingFace`/`Tokenizers` (`swift-huggingface`/`swift-transformers`, mirroring Router's own `hubProducts` versions). Verified against Router's actual source that `LiveModelLoader(downloader:tokenizerLoader:)` needs the `#hubDownloader()`/`#huggingFaceTokenizerLoader()` macros, whose expanded code requires `MLXLMCommon`/`HuggingFace`/`Tokenizers` imported at the call site — so hubProducts alone wasn't sufficient; this was confirmed empirically by a real compile failure and fixed. All three new dependency packages were already in the local/global SwiftPM cache (from building the sibling Router repo), so this added no new network fetch or MLX/C++ compilation — only linking + compiling `HuggingFace`/`Tokenizers` themselves (small, pure-Swift).

    **Ungated (runs in normal CI):**
    - `Sources/FoundationModelsMultitool/Agent/TranscriptAnalyzer.swift` — internal helper reconstructing `AgentStep`s from a Router JSONL transcript. Discriminates main-agent vs. librarian traffic via `TranscriptEvent.slot` (`.standard`/`.flash`) rather than an opaque session id — simpler and correct since each respectively only ever runs on that slot. Selects tolerant-vs-guided parsing via `TranscriptEvent.grammar` (non-nil = guided). Provides `findAPIsPrecedesRunCode`, `toolCallPaths`/`invokedToolPaths` (regex scan of runCode snippet text), `runCodeStepsBeforeFinal` (repair-turn counting), `foundAPIs(in:slot:)` (decodes the librarian's raw FoundAPIs JSON) — one helper per plan.md's four trace-assertion bullets.
    - `Tests/FoundationModelsMultitoolTests/TranscriptAssertionTests.swift` — 18 tests, all against two checked-in fixture JSONL files (`Goldens/SearchThenCallTranscript.jsonl`, `Goldens/RepairTranscript.jsonl`) plus a few inline-constructed-event cases. TDD: written first, watched fail (cannot find 'TranscriptAnalyzer' in scope), then implemented to green.
    - Total main suite: 207/207 passing (was 189 before this task).

    **Gated (opt-in via `MULTITOOL_INTEGRATION` env var, never in default CI):**
    - `Tests/FoundationModelsMultitoolIntegrationTests/Support/IntegrationGate.swift` — env-var gate, tiny profile (reuses Router's own `SmolLM-135M-Instruct-4bit`/`Qwen3-Embedding-0.6B-4bit-DWQ` refs so a machine that already ran Router's gated suite shares cached weights), `LiveRouterFixture` (resolves a real `Router`+`LiveModelLoader`, reads back `MergedTranscript.merged(under:)`).
    - `Tests/FoundationModelsMultitoolIntegrationTests/Fixtures/ScenarioTools.swift` — the four plan.md M6.5 scenario tool sets (single-call weather; tripCities+weather compose/chain; 2 relevant + 18 distractor tools; a trip-prone booking tool requiring `confirm: true`).
    - `Tests/FoundationModelsMultitoolIntegrationTests/Support/ScenarioRunner.swift` — shared scenario driver; on `GenerationError.notWiredForLiveInference` it prints a SKIP line and returns without recording any issue (Swift Testing treats a test with zero recorded issues as passed), so the typed reason produces a clean skip, not a failure, per the card's explicit ask.
    - `SearchThenCallTests.swift` (8 tests: 4 scenarios × 2 turn formats) and `PrefixReuseTests.swift` (1 test, the Finding #6 pin: asserts second `findAPIs` call latency ≤ first).

    **Important discovery, logged for whoever runs this for real:** the Router repo's `LiveModelLoader`/`ModelContainer.respond` path is now actually implemented (real MLX inference), not just gated behind `notWiredForLiveInference` as the card's framing assumed — that error is now only thrown by the *unit*-suite's stub containers. So setting `MULTITOOL_INTEGRATION=1` on a real GPU box will attempt genuine model downloads + inference, not hit the typed skip. The skip path is still correctly wired (for whatever residual environments/edge cases still throw it), but per the task's own safety/scoping note this was deliberately never exercised in this sandbox — verified structurally only (compiles; the `.enabled(if:)` trait-level gate is what actually keeps `swift test` from ever calling `LiveRouterFixture.resolve()` here).

    ## Verification performed
    - `swift build --build-tests`: clean, zero warnings from any file this task touched (one pre-existing, unrelated mlx-swift build-system warning about a bundle resource remains, present before this task too).
    - `swift test` (no env var): 207/207 main-suite tests pass; integration suite's 9 tests across 2 suites all report "skipped" (not failed), completing in 0.001s — confirmed zero downloads, zero hangs.
    - `swift test --filter TranscriptAssertionTests`: 18/18 pass in isolation.
    - `ps aux | grep -iE 'swift|xctest'` after every run: no hung processes.
    - Did NOT run with `MULTITOOL_INTEGRATION=1` set, per the task's explicit safety/scoping note (Router's live path is real now, so that would attempt genuine network downloads on this box).
  timestamp: 2026-07-03T12:26:12.321782+00:00
- actor: wballard
  id: 01kwm0356nb5xk775gdsftvyc0
  text: |-
    Adversarial double-check (via really-done) ran against the diff and returned REVISE with 3 findings. Fixed all three (bounded to one re-check round per really-done's contract):

    1. **Real bug (fixed):** `TranscriptAnalyzer.toolCallPaths(in:)`'s regex (`tools\.(...)`) had no boundary before the literal `tools`, so it matched inside longer identifiers ending in "tools" — e.g. `mytools.other({...})` incorrectly extracted `"other"` as a `tools.*` call path. Reproduced via TDD: added a failing test (`toolCallPathsIgnoresIdentifiersEndingInTools`), watched it fail exactly as predicted (`["other", "foo", "weather"]` instead of `["weather"]`), then fixed the regex with a negative lookbehind `(?<![A-Za-z0-9_$])tools\.(...)`. Confirmed green.
    2. **Style consistency (fixed):** `findAPIsPrecedesRunCode`, `invokedToolPaths`, `runCodeStepsBeforeFinal` omitted the first-argument label while their siblings `steps(in:slot:)`/`foundAPIs(in:slot:)` used `in:`. Relabeled all three to `(in steps:)` and updated every call site (`TranscriptAnalyzer.swift`'s own doc comments, `TranscriptAssertionTests.swift`, `ScenarioRunner.swift`).
    3. **Coverage gap (fixed):** added `findAPIsPrecedesRunCodeTrueWithMultipleFindAPIsCalls` (multiple `.findAPIs` steps before `.runCode`) and `foundAPIsDecodesMultipleResponsesInOrder` (two flash-slot responses decoded in order) — both paths the double-check flagged as logically-fine-by-inspection but untested.

    Re-verified fresh after the fixes: `swift build --build-tests` clean (same single pre-existing unrelated mlx-swift warning, zero new warnings); `swift test` (no env var) — 210/210 main suite green (207 + 3 new regression tests), gated suite's 9 tests across 2 suites still report "skipped" in 0.001s; `swift test --filter TranscriptAssertionTests` — 21/21 green in isolation. No hung swift/xctest processes.

    Task remains in `doing`, ready for `/review`.
  timestamp: 2026-07-03T12:43:40.117360+00:00
depends_on:
- 01KWFNVX4RFZZKEKY4C08F8V0Y
- 01KWFNWJECBNSZCANVMNTR3Z8J
- 01KWFP7Q1REW7YKJ6DZJMB9F18
position_column: doing
position_ordinal: '80'
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
- [x] `swift test` WITHOUT the env var: integration suite reports skipped, zero downloads — verified: 9 tests / 2 suites all report "skipped" in 0.001s, no network activity, no hung processes.
- [ ] With the env var on capable hardware + live Router: all four scenarios pass their trace assertions under at least one turn format, and the per-format results are recorded (test attachment or log) to settle the M4b/M4c default — **implemented but NOT executed in this sandbox** per explicit scoping/safety instruction: Router's `LiveModelLoader` path is now genuinely live (real MLX inference, real HF downloads), so running this here would attempt real network downloads. The 8 scenario tests (`SearchThenCallTests.swift`) are structurally complete, compile cleanly, and log per-format results (`print("RESULT [...] turnFormat=...")`) on every real run, but have never actually executed against a model. Needs a real run on capable hardware to close out.
- [ ] Prefix-reuse measurement passes: second findAPIs call shows no full re-prefill, or the fork() fallback is confirmed engaged (assertion, not observation) — **implemented but NOT executed**, same reason as above. `PrefixReuseTests.swift` asserts `secondElapsed <= firstElapsed` as a real `#expect`, not just an observation, but has never run against real hardware.
- [x] Transcript-parsing helpers are themselves unit-tested against checked-in fixture JSONL (runs in normal CI) — verified: 21/21 `TranscriptAssertionTests` pass against `Goldens/SearchThenCallTranscript.jsonl` + `Goldens/RepairTranscript.jsonl` (includes 3 regression tests added after an adversarial double-check found and this task fixed a real regex boundary bug in `toolCallPaths`).
- [x] Router live-path unavailable → suite skips with the typed reason, not failure — verified structurally (compiles, catch clause scoped to `GenerationError.notWiredForLiveInference`, returns without recording an issue); the live-unavailable *path itself* was not exercised since Router's live path is no longer typically unavailable (see task comment).

## Tests
- [x] `Tests/FoundationModelsMultitoolIntegrationTests/SearchThenCallTests.swift` — the four gated scenarios × two turn formats
- [x] `Tests/FoundationModelsMultitoolIntegrationTests/PrefixReuseTests.swift` — the gated prefix-reuse measurement
- [x] `Tests/FoundationModelsMultitoolTests/TranscriptAssertionTests.swift` — ungated unit tests of the JSONL trace parser on fixtures
- [x] `swift test --filter TranscriptAssertionTests` → passes in normal CI (21/21)

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.