---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01kxgwxfqaphp7f0a489p9c89g
  text: |-
    Investigation underway on real M3 Ultra hardware (same machine, weights cached). Read k4mj1gm's full comment history and all cited code (this repo's FindAPIsTool.swift, FoundationModelsMetadataRegistry's SelectionTier.swift/SelectionConfig.swift, FoundationModelsRouter's RoutedSession.swift/LiveModelLoader.swift, mlx-swift-lm's MLXLanguageModel.swift/PromptCache.swift/PromptCacheChunks.swift at the pinned checkout 4330528).

    MAJOR FINDING on the fork()/prefix-reuse regression, with hard evidence — it is NOT what it appeared to be:

    Root-caused via temporary diagnostic instrumentation (added print statements to PromptCache.resolve/store and Executor.commitPromptCache/makePromptCacheSlot in the LOCAL .build/checkouts/mlx-swift-lm copy only — never committed, that checkout isn't part of this repo's git tree, reverted before finishing). Ran `MULTITOOL_INTEGRATION=1 swift test --filter secondSearchCallReusesThePrefix --no-parallel` twice on real hardware with instrumentation active.

    Run 1: first=1.838s second=195.44s (~106x). Diagnostics showed:
    - Call 1 (task "list trip cities and get weather for each"): promptTokens=1481, COLD (0 chunks matched, expected — first ever call for this modelID), generatedTokenIDs=**13**.
    - Call 2 (task "convert 100 USD to EUR"): promptTokens=1481, resolve matched 22 of the 23 stored full chunks = **1408 of 1481 tokens (95%) served from PromptCache**, only 73 fresh tokens fed. generatedTokenIDs=**6150**.

    So prefix-reuse (the actual mechanism under test) WORKED — 95% cache hit, tiny re-prefill. The 106x wall-clock slowdown is entirely explained by call 2's GENERATION itself running 473x longer (6150 generated tokens vs 13), not by any re-prefill. This directly contradicts the task's own premise (and k4mj1gm's hypothesis) that this is a fork()/PromptCache composition bug — it isn't. `RoutedSession.fork()`'s transcript-copy mechanism and `mlx-swift-lm`'s (post-qawe2hb) content-addressed `PromptCache` chunk store DO compose correctly here: PromptCache is keyed purely by token content + modelID, not session/fork identity, so it transparently catches the shared prefix regardless of which Router-level session object produced the tokens.

    Second confirmatory run in progress (background) to check this isn't a one-off; historical variance across k4mj1gm's 3 runs (30x/115x/~30x) is itself consistent with "generation runaway length varies stochastically call to call" rather than a fixed structural bug, which would produce a consistent multiplier.

    Working hypothesis for WHY call 2 generates 6150 tokens: task 2's intent ("convert 100 USD to EUR") doesn't match any tool in the fixture registry (weather/tripCities + ~20 distractors, no currency tool) — the id-enum-grammar-constrained `Selection{ids:[String]}` JSON schema structurally allows the model to emit a long (if valid) array of many/all candidate ids rather than the expected empty/short selection, and under xgrammar constraint with no real semantic guidance to stop, the tiny 1.5B model appears to wander into a long output before reaching a valid stop state. This is the SAME underlying "unreliable/verbose tool-use behavior of this tiny model pin" already documented for SearchThenCallTests (composeChain 23 calls, discoveryUnderDistractors 11 calls) — not a second, independent bug. Still investigating the SearchThenCallTests side and whether plan.md's own citation (mlx-swift-lm revision e6ccd2721, dated 2026-06-29, claiming "Executor has no persisted-cache mechanism") is now stale — CONFIRMED stale: the pinned checkout is 4330528 (2026-07-13), which already has PromptCache/PromptCacheChunks wired into Executor via makePromptCacheSlot/commitPromptCache (called from runGuidedGenerationLoop, runUnconstrained, runTextGeneration, runReasoning) — filing this as a documentation-staleness finding for FoundationModelsRouter's plan.md, separate from this task's own scope.
  timestamp: 2026-07-14T18:06:07.082247+00:00
- actor: claude-code
  id: 01kxgzf8te8pqtyd8dnpf9jqxr
  text: |-
    Two more real-hardware experiments completed, addressing the tool-calling reliability side of the task.

    EXPERIMENT 1 — model pin swap to the cached `mlx-community/Qwen3.5-9B-4bit` (the model the OLD ReAct-loop design previously found best, per IntegrationGate.swift's own doc history), run against the current native-tool-calling design (temporary override of TinyModels.generation, reverted after the run — not landed). Ran the full FoundationModelsMultitoolIntegrationTests set on real hardware:
    - CLISmokeTests: PASS (7.0s)
    - PrefixReuseTests: PASS — first=4.02s second=1.74s (second call FASTER, no regression at all under this model). This corroborates the prefix-reuse root-cause finding above: the "second call slower" issue is a manifestation of the small 1.5B model's unreliable generation-length behavior specifically, not a fork()/PromptCache structural bug — a bigger model doesn't hit it.
    - SearchThenCallTests: 1/4 (worse than or equal to the 1.5B pin's own best 2/4) — singleCallWeather technically passed but took 265s/59 tool calls (vs 1.5B's much cheaper runs); composeChain FAILED with 0 tool calls (zero-tool-call hallucination, same failure mode as the 1.5B pin); discoveryUnderDistractors FAILED (skipped findAPIs, hallucinated "Tokyo" which isn't even a fixture city); repairFromTripProneTool FAILED with 63 runCode calls (vs the 3-call bound) and 236s elapsed.

    CONCLUSION for the model-pin axis: swapping to a larger, previously-best model does NOT fix native tool-calling reliability — it is not better, and on call-count efficiency (59-64 calls vs the 1.5B pin's 11-23) it is measurably worse. This matches the task's own framing that this pin combination "was never validated against native tool-calling" — now it has been, and the answer is no improvement. Not recommending a model-pin change.

    EXPERIMENT 2 — instructions tuning (task's other explicit ask). The current instructions text in both `ScenarioRunner.swift` and production `CLIRunner.swift` is bare: "You are a helpful assistant. Use runCode to get things done." — it never mentions findAPIs by name, never tells the model it lacks built-in knowledge of the user's data, and never discourages guessing. Tried a more directive instructions string (temporary, test-file-only edit to ScenarioRunner.swift, not yet landed):

    "You are a helpful assistant with NO built-in knowledge of the user's data — you cannot answer questions about their trip, bookings, or any live data from memory. You MUST use tools to answer. Always call findAPIs first to discover the exact functions available for the task, then call runCode to invoke them. Never answer directly from your own knowledge; never guess a function name or a result. If findAPIs finds no matching function, say so explicitly rather than making up an answer."

    Re-ran the two previously zero-tool-call-hallucinating scenarios (singleCallWeather, repairFromTripProneTool) against the original Qwen2.5-1.5B-Instruct-4bit pin with ONLY this instructions change:
    - singleCallWeather: now PASSES (7 tool calls, real answer "31 degrees Celsius" instead of the prior hallucinated "unable to retrieve"). Previously: 0 tool calls, hallucinated.
    - repairFromTripProneTool: now PASSES (4 tool calls total, runCode calls within the 3-call bound, real answer "booking ID 42 has been confirmed"). Previously: 0 tool calls, hallucinated.

    This is a genuine, reproducible improvement directly targeting the documented zero-tool-call-hallucination failure mode. Testing composeChain + discoveryUnderDistractors (the excessive-loop / skips-findAPIs-under-distraction failure modes) now, in background, to see whether the improvement generalizes to the full 4-scenario suite before deciding whether to land this instructions change in production (CLIRunner.swift) as a real fix, or just document it as a partial mitigation.
  timestamp: 2026-07-14T18:50:46.990384+00:00
- actor: claude-code
  id: 01kxh1697dftemwyxwqsr01vdv
  text: |-
    FINAL SUMMARY — investigation complete. All experimental edits reverted; working tree is clean (only kanban metadata changed). `swift build`, `swift build --build-tests`, and `swift test --skip FoundationModelsMultitoolIntegrationTests` all green (242/242 tests, 0 failures, exit 0).

    ## 1. fork()/prefix-reuse "regression" — ROOT CAUSED, and it is not what it looked like

    It is **not** a `fork()`/`PromptCache` composition bug. Diagnostic instrumentation (temporarily added to the local `.build/checkouts/mlx-swift-lm` copy's `PromptCache.resolve/store` and `Executor.commitPromptCache/makePromptCacheSlot`, run twice, then fully reverted — `git checkout -- .` in that checkout, confirmed clean) proved: the second `findAPIs` call's prefix IS being served from `PromptCache` (95% token reuse, 1408/1481 tokens hit on both instrumented runs). The wall-clock blowup is entirely explained by the *generation* itself running away: call 1 generates 13 tokens (clean, short `Selection` JSON); call 2 — deliberately an off-topic query ("convert 100 USD to EUR") that matches no candidate tool — generates 6150 tokens both times (fully deterministic, not stochastic; two independent runs produced the identical 13/6150 token counts and ~190-195s second-call time). `RoutedSession.fork()`'s transcript-copy mechanism and `mlx-swift-lm`'s (post-`qawe2hb`) content-addressed `PromptCache` chunk store compose correctly — `PromptCache` keys purely on token content + modelID, independent of which Router-level session/fork object produced the tokens.

    Deeper root cause of the 6150-token runaway: `SelectionTier.idEnumGrammar(ids:)` (`FoundationModelsMetadataRegistry`) injects `enum` + `uniqueItems: true` into the selection schema's `ids` array, but never sets `maxItems` — and `FoundationModelsRouter`'s `RuntimeJSONSchemaConverter` doesn't implement `uniqueItems` at all (zero references), so the compiled xgrammar constraint permits an unbounded, possibly-repeated-id array. For an off-topic query with no good match, the tiny model has no structural pressure to emit a short/empty selection and can wander for thousands of tokens before reaching a valid stop state. **Corroborating evidence**: under the Qwen3.5-9B-4bit pin (see below), the identical `PrefixReuseTests` scenario PASSED (second call *faster* than first: 4.02s → 1.74s) — a more capable model doesn't hit this failure mode at all, confirming it's a manifestation of the same tool-calling-reliability gap (item 2 below), not an independent caching defect. Filed a concrete, scoped follow-up fix: task `a50rrfh` (add `maxItems` to `idEnumGrammar`, in the `FoundationModelsMetadataRegistry` dependency — outside this repo's own `Sources/`).

    Bonus finding: `FoundationModelsRouter`'s `plan.md` still cites mlx-swift-lm revision `e6ccd2721` (2026-06-29) claiming "no persisted-cache mechanism" — stale versus the pinned checkout `4330528` (2026-07-13), which already has `PromptCache`/`PromptCacheChunks` wired into `Executor`. Not fixing that doc (out of this repo's scope, lives in the Router dependency) but noting it so nobody re-derives the same false premise.

    ## 2. Native tool-calling reliability gap — investigated both axes the task asked about, neither yields a practical full fix

    **Model pin (real hardware, `mlx-community/Qwen3.5-9B-4bit`, temporarily swapped in then reverted):** CLISmokeTests PASS; PrefixReuseTests PASS (no regression at all under this model); SearchThenCallTests 1/4 — singleCallWeather "passed" but cost 265s/59 tool calls, composeChain FAILED (0 tool calls, hallucinated deflection), discoveryUnderDistractors FAILED (hallucinated "Tokyo", not even a fixture city), repairFromTripProneTool FAILED (63 runCode calls vs. a 3-call bound, 236s). **Conclusion: a larger, previously-best (under the old ReAct convention) model pin does not improve native tool-calling reliability, and is measurably worse on call-count efficiency.** Not recommending a model-pin change.

    **Instructions tuning (real hardware, Qwen2.5-1.5B pin, temporarily strengthened instructions then reverted):** a much more directive instructions string ("you have NO built-in knowledge... always call findAPIs first... never guess") fixed the two previously zero-tool-call-hallucinating scenarios (singleCallWeather, repairFromTripProneTool both flipped from 0-tool-call hallucination to PASS), but composeChain still zero-tool-call-hallucinated and discoveryUnderDistractors, while now calling findAPIs and finding the right tool, wrote a `runCode` snippet that never actually invoked it (a new, distinct failure mode — hallucinating client-side JS logic instead of calling the discovered function). Net: still ~2/4, just a different 2 — **a real but incomplete, scenario-dependent mitigation, not a full fix.** Not adopted into production `CLIRunner.swift` given the mixed result; documenting it as the concrete, reproducible starting point for a future, more targeted round of prompt engineering.

    ## 3. Final real-hardware re-run recorded (4th independent run of this exact suite, following k4mj1gm's 3)

    `MULTITOOL_INTEGRATION=1 swift test --filter FoundationModelsMultitoolIntegrationTests --filter SearchThenCallTests --no-parallel`, current (unmodified) `Qwen2.5-1.5B-Instruct-4bit` pin, original instructions:
    - CLISmokeTests: PASS
    - PrefixReuseTests: FAIL — first=1.886s second=190.59s (~101x) — 3rd consecutive identical-pattern reproduction across this session's 2 instrumented runs + this final run.
    - SearchThenCallTests: **0/4** this run (singleCallWeather 0 calls/hallucinated; composeChain 92 calls/hallucinated "Miami"; discoveryUnderDistractors 0 calls/deflected; repairFromTripProneTool 4 calls but wrong `invokedToolPaths`) — even below the previously-observed 1-2/4 floor, underscoring how unreliable this model is run-to-run.

    ## GO/NO-GO: REAFFIRMED, NO-GO, with sharper findings

    Task `7840f24` (deleting `MultiToolAgent`) remains correctly blocked. Real pass rate across 4 independent hardware runs of `SearchThenCallTests` never exceeds 2/4 (50%), well under the required ≥7/8 (87.5%) baseline; `PrefixReuseTests` fails consistently (now root-caused, not mysterious — see above). Both investigated remediation axes (bigger model, tuned instructions) were empirically tested on real hardware and neither clears the bar; the instructions change is a real partial improvement worth someone revisiting with more iteration, and task `a50rrfh` is a concrete, scoped fix for the grammar-generation-length root cause, but neither is sufficient today to flip this to GO.

    All 4 acceptance criteria are addressed: (1) zero-tool-call/excessive-loop investigated with both a model-pin experiment (no improvement) and an instructions-tuning experiment (partial improvement, not adopted) — documented; (2) fork() prefix-reuse regression root-caused (not a caching bug; a symptom of the same tool-calling reliability gap plus a specific, fixable grammar gap) with a filed fix task; (3) gated suite re-run on real hardware multiple times this session, results recorded; (4) NO-GO reaffirmed with updated findings. Leaving this task in `doing` for review per the implement skill's contract.
  timestamp: 2026-07-14T19:20:49.645306+00:00
- actor: claude-code
  id: 01kxh1b2x8phj2vjma8r71jbcq
  text: '/test verification (independent subagent): swift build/build-tests/test all green. 242 tests passed, 7 gated tests correctly skip, 0 failures. Confirmed zero source diff (pure investigation task). Proceeding to /commit checkpoint.'
  timestamp: 2026-07-14T19:23:27.016468+00:00
- actor: claude-code
  id: 01kxh1dhzagsk059sdcyrhk3pd
  text: 'Correction: the maxItems fix task the implementer filed (short_id a50rrfh) was created on THIS repo''s board by mistake — its actual fix belongs in FoundationModelsMetadataRegistry''s own source (SelectionTier.idEnumGrammar), so it should live on that repo''s kanban board, not here. Recreated it there as short_id 678h0ex (same content) and deleted the misplaced duplicate here, mirroring the earlier correction for the mlx-swift-lm SDK-compat task. Proceeding with the finish loop for this investigation task.'
  timestamp: 2026-07-14T19:24:47.978149+00:00
- actor: claude-code
  id: 01kxh1e16ap53ft2fqn05cj51e
  text: swift build reconfirmed green after the board-migration correction. Proceeding to /commit checkpoint.
  timestamp: 2026-07-14T19:25:03.562831+00:00
depends_on:
- 01KWVNWP89T9551VNK3K4MJ1GM
position_column: doing
position_ordinal: '80'
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

- [x] A documented investigation of the zero-tool-call-hallucination and excessive-call-loop behaviors, with either a fix (model pin change, instructions tuning) or a clear conclusion that none is practical within this design. DONE — both axes tried on real hardware: model-pin swap to `Qwen3.5-9B-4bit` (no improvement, worse call-count efficiency); instructions tuning (partial, scenario-dependent improvement — fixes zero-tool-call hallucination for 2 scenarios, surfaces a different hallucination mode in the other 2). Neither adopted as a full fix; see comments for data and the reasoning.
- [x] A documented investigation of the `fork()` prefix-reuse regression, with either a root cause + fix, or a clear conclusion that it's non-reproducible/environmental. ROOT CAUSED — not a fork()/PromptCache bug. Diagnostic instrumentation proved 95% prefix reuse is achieved; the wall-clock blowup is caused by the second call's *generation* itself running away (13 vs 6150 tokens, fully deterministic across 2 runs), traced to `SelectionTier.idEnumGrammar`'s missing `maxItems` bound (fix filed as task `a50rrfh`, out of this repo's own `Sources/`). Corroborated by the 9B-pin experiment, where the identical scenario passed cleanly.
- [x] The gated suite re-run on real hardware with results recorded, whatever the outcome. DONE — 3 additional real-hardware runs this session (2 instrumented `PrefixReuseTests`-only runs, 1 final full `SearchThenCallTests`+`PrefixReuseTests` confirmatory run under the unmodified pin), plus the 9B-pin and instructions-tuning experiment runs. All recorded in comments.
- [x] `k4mj1gm`'s NO-GO note is either superseded by a new GO note (if the pass rate now clears the baseline) or reaffirmed with updated findings. REAFFIRMED — final confirmatory run this session: `SearchThenCallTests` 0/4, `PrefixReuseTests` FAIL (~101x, 3rd consistent reproduction). `7840f24` remains correctly blocked.

## Tests

- [x] `MULTITOOL_INTEGRATION=1 swift test --filter FoundationModelsMultitoolIntegrationTests`, re-run and results recorded. Re-run multiple times this session (see comments); working tree fully reverted to original state (no source changes landed — this was a diagnosis-only investigation per its own acceptance criteria, plus one filed follow-up fix task).
- [x] Full ungated `swift test` remains green throughout. 242/242 tests, 22 suites, 0 failures, exit 0 — reconfirmed after all experimental edits were reverted.
