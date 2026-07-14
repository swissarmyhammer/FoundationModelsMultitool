---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01kxgraxb3x8bn35esjc7bngsw
  text: |-
    Investigated and built. Summary:

    **Research (verified against the shipping SDK's `.swiftinterface`, `Evaluations.framework`'s `Evaluations.swiftmodule/*.swiftinterface` under `xcrun --show-sdk-path`'s toolchain — same approach the retired `AgentEvaluation.swift`'s own doc comment used):**
    - `FoundationModels.Transcript` → `Evaluations.StructuredTranscript` conversion is free: the `Evaluations` module ships `extension FoundationModels.Transcript { var structuredTranscript: Evaluations.StructuredTranscript { get } }` directly. No adapter needed — `session.transcript.structuredTranscript` is all it takes.
    - `Evaluations.ToolCallEvaluator<Input>` requires `Input.Expectation == TrajectoryExpectation` and grades a fixed `Evaluations.ModelSubject<Input.ExpectedValue>` (the framework's own struct, not a custom `Subject` conformer like the retired `AgentSubject`).
    - Mapped against the retired suite's 3 metrics (`AgentEvaluators.swift`'s `AgentMetricName`): **`SearchedThenCalled`** (findAPIs precedes runCode) generalizes cleanly via `TrajectoryExpectation(ordered: [ToolExpectation("findAPIs"), ToolExpectation("runCode")])`. **`CalledExpectedTools`** (which `tools.*` paths a runCode snippet invokes) *partially* generalizes — `ArgumentMatcher` actually has 9 cases (not 4 as I first mis-surveyed; corrected after an adversarial review caught it), including `.contains(argumentName:substring:)`, so a `runCode` `ToolExpectation` can assert its `code` argument contains each expected `tools.<path>(` call site. What it can't express is the retired evaluator's *exact-set* check (invoked == expected, no more no fewer) — no "argument does NOT contain" primitive exists — so that exclusivity half stays `SearchThenCallTests`' own `NativeTranscript.invokedToolPaths(in:)` set-equality `#expect`. **`RepairedWithinN`** (a call-count ceiling) does NOT generalize at all — `TrajectoryExpectation`'s `ordered`/`unordered`/`disallowed`/`allowsAdditionalCalls` have no cardinality-bound concept — stays `NativeTranscript.toolCallCount(in:named:)`'s job.

    **Built:** `Tests/FoundationModelsMultitoolIntegrationTests/NativeToolCallEvaluation.swift` — a new `Evaluations.Evaluation` conformer (`NativeToolCallEvaluation`) reusing `SearchThenCallTests`' own 4 scenarios (tool sets/prompts verbatim, scenario 3's prompt reworded for dataset-lookup uniqueness, same fix the retired file applied), graded via the framework's built-in `ToolCallEvaluator` producing `allPass`/`percentagePass` metrics aggregated with mean/stddev across samples — the statistical payoff `SearchThenCallTests`' one-shot `#expect`s don't give. Gated the same way (`.enabled(if: multitoolIntegrationEnabled)`, `NativeToolCallEvaluationTests` suite).

    **Adversarial review (really-done's double-check gate):** round 1 REVISE — caught my `ArgumentMatcher` case-count error (fixed by actually porting the presence-based `CalledExpectedTools` check instead of dismissing it), a doc gap around `subject(from:)` not catching `GenerationError.notWiredForLiveInference` like `ScenarioRunner` does (documented explicitly as an inherited limitation from the retired file, not silently mirrored), and a misleading scenario-4 comment (reworded). Round 2: PASS.

    **Real hardware:** one `MULTITOOL_INTEGRATION=1 swift test --filter NativeToolCallEvaluationTests` run attempted (weights already cached locally — `Qwen2.5-1.5B-Instruct-4bit`/`Qwen3-Embedding-0.6B-4bit-DWQ`, same pin `IntegrationGate.swift` uses). Result: hit its `.timeLimit(.minutes(30))` wall before any of the 4 scenarios' live sessions completed (`aggregateValue(.mean(...))` returned `-1.0`, i.e. zero samples finished) — consistent with the per-scenario cost profile `k4mj1gm` already documented (individual scenarios up to 692s on a bigger model; here it's 4 *sequential* fresh `LiveRouterFixture` resolutions, each a real model load + live generation, on this smaller pinned model). Bumped the suite's `.timeLimit` to `.minutes(60)` for headroom on a future run; did not re-attempt the full run in this session (would cost another 30-60+ min, and this task is explicitly optional/exploratory scope). A confirming real-hardware pass/fail run against the raised limit is a natural follow-up, not done here.

    **Verification:** `swift build`, `swift build --build-tests`, and `swift test` all green (242/242 main-suite tests, 22 suites, 0 failures; all 4 gated suites — including the new one — skip cleanly with zero network/live-inference activity when `MULTITOOL_INTEGRATION` is unset).

    Leaving in `doing` for review per the implement skill's contract.
  timestamp: 2026-07-14T16:46:04.131446+00:00
- actor: claude-code
  id: 01kxgrdzhk20m9669v53j3djk5
  text: '/test verification (independent subagent): swift build/build-tests/test all green (ran twice for reproducibility). 242 tests passed, 7 gated tests correctly skip (including the new nativeToolCallEvaluation() test), 0 failures. Proceeding to /commit checkpoint.'
  timestamp: 2026-07-14T16:47:44.691427+00:00
depends_on:
- 01KWVNWP89T9551VNK3K4MJ1GM
position_column: doing
position_ordinal: '80'
title: Port AgentEvaluation's Evaluations-framework scoring to grade native LanguageModelSession transcripts
---
## What

Part of the MultiToolAgent removal pivot follow-up (see board, task `k4mj1gm`).

`Tests/FoundationModelsMultitoolIntegrationTests/AgentEvaluation.swift` was retired (deleted) as part of `k4mj1gm`'s port of the gated integration suite to the native `LanguageModelSession`-driven design. It was irreducibly built on `AgentStep`/`AgentSubject`/`TranscriptAnalyzer.steps(slot:.standard)` — `MultiToolAgent`'s own hand-rolled ReAct-loop transcript shape, which a native `LanguageModelSession`'s main loop never produces (that loop isn't Router-recorded at all; only `findAPIsTool`'s own selection tier still is).

`AgentEvaluation.swift`'s own doc comment (pre-deletion) noted that Apple's `Evaluations` framework ships real, usable machinery for exactly this shape that specifically did *not* apply to `MultiToolAgent`'s output:

- `ModelSample.expectations: TrajectoryExpectation?` — graded by `Evaluations.ToolCallEvaluator` against `Evaluations.StructuredTranscript`, both of which read `FoundationModels.Transcript.ToolCall` directly.

Now that the gated suite drives a real `LanguageModelSession` with a real `FoundationModels.Transcript` (see `k4mj1gm`'s `Support/ScenarioRunner.swift` and `Support/NativeTranscript.swift`), this previously-inapplicable Apple framework machinery becomes directly usable: `session.transcript` can likely be adapted into `Evaluations.StructuredTranscript` and graded via `Evaluations.ToolCallEvaluator` against a `TrajectoryExpectation`, replacing the `AgentEvaluators.swift`/`AgentSubject`-based custom `EvaluatorProtocol` conformers (`SearchedThenCalledEvaluator`, `CalledExpectedToolsEvaluator`, `RepairedWithinNEvaluator`) with the framework's own built-in evaluators.

This would give the M6.5a-equivalent scenarios statistical mean/stddev aggregation across repeated samples (the `Evaluations` framework's whole point), rather than the current one-shot per-scenario `#expect` assertions `SearchThenCallTests` now performs.

## Scope

- Investigate `Evaluations.ToolCallEvaluator`/`Evaluations.StructuredTranscript`/`TrajectoryExpectation`'s actual API shape (check the shipping SDK's `.swiftinterface`, same approach `AgentEvaluation.swift`'s own doc comment used — see `xcrun --show-sdk-path`, `Evaluations.framework`'s `.swiftmodule/*.swiftinterface`).
- Determine whether/how a `FoundationModels.Transcript` converts into `Evaluations.StructuredTranscript` (may need a small adapter).
- If it fits cleanly: build a new `Evaluations.Evaluation` conformer (mirrors the retired `AgentEvaluation`'s shape: `dataset`, `subject(from:)` driving a real gated scenario, `evaluators`, `aggregateMetrics`) reusing `SearchThenCallTests`' own scenario tool sets/prompts as the dataset, graded via the framework's built-in `ToolCallEvaluator` instead of custom `AgentEvaluators.swift` conformers.
- If it does NOT fit cleanly (API mismatch, missing hooks, etc.): document why not, same rigor as the retired file's own SDK-pin documentation.
- This is optional/exploratory scope, not a blocking gate — `k4mj1gm`'s own acceptance criteria did not require this port; the gated suite's existing per-scenario `#expect` assertions already cover the same three properties (search-then-call ordering, called-expected-tools, repaired-within-n) without it.

## Tests

- If built: a new gated eval suite (mirrors the retired `AgentEvaluationTests`), `.enabled(if: multitoolIntegrationEnabled)`, run on real hardware with results recorded.
- Full ungated `swift test` remains green throughout (the whole suite must stay `.enabled(if:)`-gated, zero downloads/live inference by default).
