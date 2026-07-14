---
assignees:
- claude-code
depends_on:
- 01KWVNWP89T9551VNK3K4MJ1GM
position_column: todo
position_ordinal: '8980'
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
