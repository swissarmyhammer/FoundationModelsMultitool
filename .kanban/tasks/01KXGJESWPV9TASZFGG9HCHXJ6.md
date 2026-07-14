---
assignees:
- claude-code
depends_on:
- 01KWVNWP89T9551VNK3K4MJ1GM
position_column: todo
position_ordinal: 8a80
title: Investigate native tool-calling reliability gap and fork() prefix-reuse regression surfaced by the ported gated integration suite
---
## What

Part of the MultiToolAgent removal pivot follow-up (see board, task `k4mj1gm`).

`k4mj1gm` ported the gated `MULTITOOL_INTEGRATION=1` integration suite (`Tests/FoundationModelsMultitoolIntegrationTests/`) to the native `LanguageModelSession`-driven design and ran it for real on Apple Silicon hardware (M3 Ultra, `mlx-community/Qwen2.5-1.5B-Instruct-4bit`). The port itself is confirmed correct (its assertions detect both success and failure correctly — `CLISmokeTests` and `composeChain` passed cleanly), but the real pass rate (2/6, 1/4 on the `SearchThenCallTests`-equivalent) is far below the old design's ≥7/8 baseline, and this task's own go/no-go note recorded a **NO-GO** for `7840f24` (deleting `MultiToolAgent`) on this evidence. See `k4mj1gm`'s task comments for the full run log analysis.

Two distinct, real problems were surfaced:

1. **Native tool-calling reliability gap.** The pinned tiny model frequently emits **zero tool calls at all** for prompts that obviously need one (`singleCallWeather`, `repairFromTripProneTool` both got a hallucinated direct answer, never touching `findAPIs`/`runCode`), and when it does call tools, it can burn many more calls than expected without reliably reaching a correct answer (`composeChain`: 23 calls for what should be ~2; `discoveryUnderDistractors`: 11 calls, never called `findAPIs` at all under the ~20-tool distractor surface, then hallucinated an answer). This is a real behavioral regression versus the retired `ACTION:`/`TASK:`/`CODE:` prompted-text convention, which structurally forced a parseable action out of the model every turn — native tool-calling instead relies on the model's own trained tool-use propensity, which this tiny pin doesn't reliably have.

2. **`fork()`-based prefix reuse regression.** `PrefixReuseTests`' second `findAPIs` call (expected no slower than the cold first call, per Finding #6) was ~30x SLOWER (7.5s -> 227.3s) on the real run, the opposite of the expected property. Root cause unknown — could be a real regression in the selection tier's `fork()` mechanism under this design, or an environment/thermal/memory-pressure artifact of one long-lived process making many GPU calls. Needs isolated reproduction before concluding either way.

## Scope

- **Tool-calling reliability**: investigate whether a different/larger tool-calling-capable model pin improves native tool-calling reliability for this suite (mirror the old suite's own `TinyModels` doc-comment history of multi-model comparisons — `Qwen2.5-0.5B` -> `Qwen2.5-1.5B` -> `Qwen3.5-2B-mxfp4` -> `Qwen3.5-9B` -> back to `Qwen2.5-1.5B` — this pin was never validated against *native* tool-calling, only the old prompted convention). Also investigate whether tuning the session's `instructions` text more strongly toward tool use changes the zero-tool-call-hallucination rate.
- **Prefix-reuse regression**: reproduce `PrefixReuseTests`' second-call slowdown in isolation (repeat runs, vary surface size, check for thermal/memory-pressure confounders, inspect whether `FindAPIsTool`'s selection tier's `fork()` call path changed behavior versus the old `MultiToolAgent.makeFindAPISearcher`-based path it replaced). Determine if this is a real regression requiring a fix upstream (`FoundationModelsMetadataRegistry`'s `SelectionTier`, or `FoundationModelsRouter`'s `RoutedSession.fork(workingDirectory:)`), or an artifact of this specific run.
- Once either or both are resolved (or a different, well-reasoned path forward is identified), re-run `MULTITOOL_INTEGRATION=1 swift test --filter FoundationModelsMultitoolIntegrationTests` and update `k4mj1gm`'s go/no-go note (or this task's own follow-up comment) with the new pass rate, to potentially clear `7840f24` to proceed.

## Acceptance Criteria

- [ ] A documented investigation of the zero-tool-call-hallucination and excessive-call-loop behaviors, with either a fix (model pin change, instructions tuning) or a clear conclusion that none is practical within this design.
- [ ] A documented investigation of the `fork()` prefix-reuse regression, with either a root cause + fix, or a clear conclusion that it's non-reproducible/environmental.
- [ ] The gated suite re-run on real hardware with results recorded, whatever the outcome.
- [ ] `k4mj1gm`'s NO-GO note is either superseded by a new GO note (if the pass rate now clears the baseline) or reaffirmed with updated findings.

## Tests

- [ ] `MULTITOOL_INTEGRATION=1 swift test --filter FoundationModelsMultitoolIntegrationTests`, re-run and results recorded.
- [ ] Full ungated `swift test` remains green throughout.
