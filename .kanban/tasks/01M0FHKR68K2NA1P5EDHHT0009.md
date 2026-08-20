---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0fsbt351gsxvvdf2794nwaq
  text: |-
    ## Evidence pulled from CI run 32294279325 (job 96202753110, "Integration (real models, real GPU)")

    Pulled the integration job's own log with `gh run view 32294279325 --job 96202753110 --log`. Key lines (GitHub's per-line timestamps in this log are batched/misleading — the whole "AsyncFanOutTests -> ElevationTests" block shares one flush timestamp despite spanning ~2000s of real process time; the process's own `Date()`-computed `elapsed=` and Router's own `STALL withoutProgress=` values are the trustworthy clock):

    ```
    RESOLVED [multitool-cli-demo] context=32768 tokens standard=mlx-community/Qwen3.8-27B-mxfp4 footprint=20833850079B charged=20833850079B | flash=mlx-community/Qwen3.8-27B-mxfp4 footprint=20833850079B charged=2576980378B
    STALL withoutProgress=30.2s ... visibility=fragments(observed: 0)
    STALL withoutProgress=60.9s ... visibility=fragments(observed: 0)
    ... (STALL fires every ~30s, "observed: 0" fragments every single time, all the way to)
    STALL withoutProgress=1763.4s ... visibility=fragments(observed: 0)
    ✘ Test "..." recorded an issue at ElevationTests.swift:29:6: Time limit was exceeded: 1800.000 seconds
    SCENARIO [elevationInCodeMode] result=FAIL validAnswer=fail pendingEnvelope=fail
    RESULT [elevationInCodeMode] elapsed=1793.2239320278168s toolCalls=0 toolOutputs=0 pendingEnvelopes=0 priming=off textResets=0 compactions=0 tokens=n/a failedCalls=0 reply=""
    ✘ Test "..." failed after 1800.268 seconds with 3 issues.
    ```

    ## What this rules out (repo-owned code checked, no bug found)

    1. **`LiveProfileTurnstile`/`LiveRouterFixture.resolve()`** (`IntegrationTests/.../Support/LiveRouterFixture.swift`): `enter()` is taken before resolving, `leave()` is only called after `await profile.release()` completes in `tearDown()`, on every exit path (`withLiveRouterFixture`'s do/catch covers success, thrown error, and the typed skip). Ordering is correct; nothing here can leak the turnstile.
    2. **Suite ordering** (item 4 of the card): suites run alphabetically by file name under `--no-parallel` (`AsyncFanOutTests` -> `ElevationTests` -> `InBandCollectionCanaryTests` -> ...). The suite immediately before this one (`AsyncFanOutTests`, `fanOutOverTwoStockTools`, 211s) completed and graded PASS; the suite immediately after (`InBandCollectionCanaryTests`) resolved a *fresh* profile and passed both scenarios, one of which (`inBandCollection`) itself ran 1128.7s of real generation successfully. So the shared `LiveProfileTurnstile`/model-container path is provably not globally broken in this run — a hang isolated to this one scenario, bracketed by successful real generation on the identical model both before and after.
    3. **`scenarioDiscoveryPriming`** is `nil` (`ScenarioRunner.swift`) — priming is off for every scenario in this target, so seeding isn't a factor. `priming=off` in the RESULT line confirms this, not a failure.
    4. **The suite's own timeout posture is deliberate, not an oversight**: `ScenarioRunner.swift`'s `streamTurn` documents at length (next to `.generationStalled`) that a `STALL` is *reported, never asserted on* — Router declined to impose a timeout, and a scenario that failed on stall would be "re-imposing the timeout Router declined to impose," conflating "generating steadily and achieving nothing" (`^wnfzwxg`'s shape) with genuine total stall. This run's `visibility=fragments(observed: 0)` on every single STALL, for the *entire* 1793s, is the second, more severe shape the comment already names as distinct — literally zero tokens, not wasted-but-moving generation.
    5. **`Sources/FoundationModelsMultitool/` and `Sources/MultitoolCLI/CLIRunner.swift`** (item 5 of the card): no unbounded/untimed gate wait of our own in the path this scenario drives before its first tool call — `makeSession(tools:discoveryPriming:)` is synchronous, and `streamEvents(to:)` is the Router-vended stream this repo only consumes.

    ## Named cause: hypothesis, not proof

    `toolCalls=0` + `reply=""` + `STALL ... observed: 0` for the entire 1793s means the model's *very first* generated token, on the very first turn, never arrived — the hang is upstream of anything this scenario's tool surface, elevation mechanism, or grading touches. `CLIRunner.swift` (around `demoProfile`) documents that `standard` and `flash` both name the *same* model reference (`Qwen3.8-27B-mxfp4`) deliberately, which Router resolves to **one shared resident container with one `generationGate`** — and that container-sharing shape is already the site of a known, currently-worked-around Router defect (`^1zt7vyg`, permit held for the whole turn including tool rounds; regression-guarded here by `NestedGenerationProbeTests`, which passed in this same CI run). My best-supported hypothesis is a variant of that same container-sharing hazard: a stale/leaked `generationGate` permit state on container reuse across scenario boundaries (this scenario's fresh `resolve()` racing the tail of the *previous* scenario's container teardown), rather than the already-fixed in-turn nested-generation case `^1zt7vyg`/`NestedGenerationProbeTests` cover. I cannot verify this without Router's source — `RoutedModel`/`AsyncSemaphore`/container-pooling internals live in `FoundationModelsRouter`, a sibling package this project must not edit directly (memory rule: sibling repo work goes to its own agent/card).

    **I could not reproduce this locally** (task forbids running the 30-minute suite myself, and the card notes it already passed locally in 51.79s on `^dwzkfzx`), so I cannot conclusively name the cause — only this evidenced hypothesis. Per the card's own instruction, I am leaving this honestly incomplete rather than fabricating a fix: **no code change was made to try to fix the hang.** The two "cause" and "fix" acceptance boxes stay unchecked below.

    ## Completed this pass

    - Renamed the suite in `ElevationTests.swift`: `"Gated elevation-in-code-mode scenario (phase-1 exit)"` -> `"Elevation-in-code-mode scenario (phase-1 exit)"`, and the leading doc comment `"The gated elevation-in-code-mode scenario"` -> `"The elevation-in-code-mode scenario"`. Grepped the file for `[Gg]ated` after editing: no matches left. (Every *other* suite file in this target still says "Gated" too, e.g. `AsyncFanOutTests.swift`, `SearchThenCallTests.swift` — out of scope for this card, which named only `ElevationTests.swift`.)
    - `swift build --package-path IntegrationTests --build-tests`: clean, "Build complete! (5.58 sec)".
    - Root `swift test`: green — "Test run with 367 tests in 32 suites passed after 5.492 seconds."
    - Did **not** run the real-model integration suite (forbidden by the card/orchestrator).

    ## Recommendation for next step

    File a card on the `FoundationModelsRouter` sibling board describing this symptom (zero-token, zero-fragment total stall on a fresh `resolve()` immediately following another scenario's teardown of the same shared-reference container) and pointing at `^1zt7vyg` as the related, already-tracked defect class, asking whether container/`generationGate` state can leak across a `release()`/re-`resolve()` boundary. I have not filed that card yet — leaving that decision to the user/orchestrator since it requires judgment about whether the evidence here is strong enough to escalate, and per the review-gate process this task stays in `doing` for review first.
  timestamp: 2026-08-20T14:31:53.189221+00:00
- actor: claude-code
  id: 01m0fschewnkmcffrr9mnjd961
  text: |-
    ### implement — changed
    - evidence: 1 file changed — IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/ElevationTests.swift (suite name + doc comment renamed off "Gated"). Investigated CI run 32294279325's integration job log directly via `gh run view --job --log`; hypothesis and evidence recorded in the comment above. `swift build --package-path IntegrationTests --build-tests` clean (5.58s). Root `swift test` green: 367 tests in 32 suites passed (5.492s). Did not run the real-model suite (explicitly out of scope this pass) and did not apply any fix, since no structural bug was found in this repo's own code — the evidence points at Router (sibling package) container/generationGate sharing, which cannot be confirmed or fixed here.
    - next: leaving in `doing` for review, per process. Recommend the reviewer/orchestrator decide whether to escalate a card to the FoundationModelsRouter board with this evidence.
  timestamp: 2026-08-20T14:32:17.116245+00:00
- actor: claude-code
  id: 01m0ft1mp28rdkbb1qbmkaf7tp
  text: |-
    ## Correction: the `^1zt7vyg` hypothesis in my previous comment is REFUTED, not just unconfirmed

    The coordinator checked it against Router's actual history and it does not hold. I re-verified both points myself in the local `FoundationModelsRouter` checkout (`/Users/wballard/github/swissarmyhammer/FoundationModelsRouter`):

    1. **`^1zt7vyg` is done, not "currently worked around."** `git merge-base --is-ancestor 8db8094 0f4b274e4f228343cdfb99b016be3cc054f8f934` returns true in that checkout. `0f4b274...` is the exact revision this repo's `Package.resolved` pins (`foundationmodelsrouter 0f4b274e4f228343cdfb99b016be3cc054f8f934 main`) — the revision CI actually built on 2026-08-19. The real behavior fix is commit `14dd016` ("lend the generation permit to a nested turn on another session"); `8db8094` on top of it is a pure argument-label rename with no behavior change. So the fix was live in the CI run that hung.
    2. **The symptom shape doesn't fit regardless.** Reading `GenerationPermitLoan`'s call site in `Sources/FoundationModelsRouter/Session/RoutedSessionActorTurnExecution.swift`: the loan exists so a tool call *made from inside an in-flight turn* can reuse that turn's permit on the same shared container, instead of deadlocking waiting for a permit only the outer turn's own end would free. It requires a turn already in flight and a nested call reentering the same container. Our hang has `toolCalls=0, toolOutputs=0` for the entire 1793s — no tool call, nested or otherwise, ever happened. The precondition for `^1zt7vyg`'s defect (and its fix) never engages.

    I am retracting that hypothesis. It does not belong on this card as an answer.

    ## New evidence this pass, addressing the coordinator's four directions

    **Was the call ever dispatched, or stuck earlier (tool-surface construction / `MultiTool.Builder` / search-tier setup)?** Dispatched. Read `RoutedSessionActorTurnExecution.swift`: `beginGenerationStallWatch()` and the `modelCall = Task { ... try await body(composedPrompt) ... }` that actually calls into the backend are created together, *after* `ToolContext`/`GenerationPermitLoan` setup and prompt composition already completed. Router's own doc on `GenerationStall`/`GenerationProgressVisibility.fragments(observed:)` (`Sources/FoundationModelsRouter/Session/GenerationStall.swift`) states `timeWithoutProgress` for a streaming turn is measured from the last fragment, or — before the first fragment — "falls back to the start of the model call." So every `STALL ... visibility=fragments(observed: 0)` line in the CI log, all the way to `withoutProgress=1763.4s`, is timed from model-call dispatch, not from earlier setup. Tool-surface construction, `MultiTool.Builder`, registry/search-tier setup, session construction, and prompt composition all necessarily completed *before* this window started. The hang is inside the backend's actual generation call (`body(composedPrompt)` → `MLXFoundationModelsSessionBackend`/`mlx-swift-lm`, pinned `mlx-swift-lm @ acc920594fad346e416a0f633d96bd712d868460`), not in anything this repo or Router's higher-level turn/tool plumbing owns.

    **Resident vs. cold load — does `elapsed=1793.2s` include model loading?** No. Model residency/loading (however long it took) is entirely prior to and outside the stall-watch window by construction (see above) — `RESOLVED [...]` prints, then `let start = Date()` in `ScenarioRunner.swift`, then `streamTurn` is entered; the stall clock inside Router starts even later, at `body(composedPrompt)` dispatch. So "cold load" cannot be inflating the 1793s figure. Separately confirmed: `LiveRouterFixture.resolve()` builds a brand-new `Router` with a brand-new temp `cacheDir`/`recordingsDir` on every call (no static/shared caching anywhere in this repo's fixture code) — every suite and every test within a suite resolves fresh, including the two tests inside `InBandCollectionCanaryTests` (the CI log shows a fresh `RESOLVED [...]` line before each).

    **Complexity differences vs. the suites on either side:** `AsyncFanOutTests` and `ElevationTests` both declare `.serialized, .timeLimit(.minutes(30))`. `InBandCollectionCanaryTests` declares `.timeLimit(.minutes(62))` — explicitly *re-derived* (not just raised) on card `^nhxj8hx` from real, heavy, legitimate multi-minute generation cost specific to that scenario (measured tokensOut in the thousands even on "cut off" runs, never zero). Applying `^nhxj8hx`'s own re-derivation method to `ElevationTests`'s recorded 51.79s local baseline (× ~6.21 CI-slowdown factor measured on that same card × 4/3 margin) predicts roughly 5.4 minutes for a CI-adjusted healthy run — far under the existing 1800s ceiling. So the 30-minute ceiling was not too tight for a legitimately-slow-but-real pass; this run produced zero tokens, not a lot of slow ones, which is a different failure shape than the one `^nhxj8hx` fixed. Tool-surface shape is not the differentiator either: `inBandCollection` (`theModelCollectsItsOwnBackgroundRun`, the scenario that *did* succeed in this same run, 1128.7s, `waitCalls=3`) uses the same non-direct surface as `elevationInCodeMode` — `searchTools`/`runCode`/`wait` all mounted, `direct: false` (the default) in both. (The *other* in-band test, `theDelayedEchoRoundTripsThroughItsHandle`, does pass `direct: true`, but that's not the one that matches `elevationInCodeMode`'s shape — `inBandCollection` is the closer comparison and it also runs non-direct.) Prompt lengths are comparable single-sentence requests in both. No declared-complexity difference explains the hang.

    **Could the CI log show the actual dispatched prompt/tokens?** No — `LiveRouterFixture.resolve()`'s `recordingsDir` (the `.full`-level Router transcript that would carry this) is a fresh `FileManager.default.temporaryDirectory`-rooted UUID directory per fixture, never uploaded as a CI artifact, and no longer exists for this run. This is a real gap: nothing survives from CI that shows what was actually sent to the model for this specific hung turn beyond what got printed to stdout (which is exactly the STALL/RESULT lines already quoted). Worth a follow-up (upload the recording dir as a CI artifact on integration-job runs) but that is a forward-looking improvement, not a fix for this card.

    ## Where this leaves the cause

    **Still investigating — `^1zt7vyg` ruled out.** The hang is real (zero streamed fragments for at least 1763s of genuine in-flight backend generation time, confirmed via Router's own instrumentation semantics), is dispatched correctly (not stuck in this repo's or Router's setup/tool-surface code), is not explained by cold-load time, is not explained by a declared-complexity/ceiling mismatch, and is not explained by a tool-surface-shape difference from the scenario that succeeded around it in the same run. I do not have a pinned cause. I am not fabricating a fix. No code change was made to address the hang itself this pass (the suite-name rename already recorded stands on its own).
  timestamp: 2026-08-20T14:43:48.546789+00:00
- actor: claude-code
  id: 01m0ft2k7m7nh80c63atjvgnaa
  text: |-
    ### implement — no-change
    - evidence: no files changed this pass (the `ElevationTests.swift` rename from the prior pass stands). Retracted the refuted `^1zt7vyg` hypothesis with evidence (`git merge-base --is-ancestor 8db8094 0f4b274e4f228343cdfb99b016be3cc054f8f934` → true in the local `FoundationModelsRouter` checkout, confirming the fix predates the CI-pinned revision; and the `toolCalls=0` mismatch against `^1zt7vyg`'s in-flight-nested-call precondition). Followed the coordinator's four directions: confirmed via `RoutedSessionActorTurnExecution.swift`/`GenerationStall.swift` that the stall window starts at model-call dispatch (so the call was dispatched, not stuck in tool-surface/registry setup, and cold-load time is excluded from the 1793s figure); confirmed `LiveRouterFixture.resolve()` never caches a profile across suites/tests; compared `.timeLimit`/tool-surface-shape/prompt-length against `AsyncFanOutTests` and `InBandCollectionCanaryTests` and found no declared-complexity difference that explains a zero-fragment stall, including applying `^nhxj8hx`'s own ceiling re-derivation method to this suite's local baseline (predicts ~5.4 min CI-adjusted, well under the existing 1800s limit). No forensic transcript survives from the CI run (ephemeral temp dir, not uploaded as an artifact) to inspect the literal dispatched request. Root cause remains unpinned; card now reads "still investigating, ^1zt7vyg ruled out" rather than carrying a refuted hypothesis as the answer.
    - next: leaving in `doing` for review. No further avenue for pinning the cause without either a CI transcript-upload change (forward-looking, separate from this card) or a live reproduction, both out of reach this pass.
  timestamp: 2026-08-20T14:44:19.828729+00:00
position_column: doing
position_ordinal: '8380'
title: 'ElevationTests hangs on CI: 30 minutes, zero tool calls, empty reply'
---
CI run `32294279325` (push `563a483`, 2026-08-19): the suite \"Gated elevation-in-code-mode scenario (phase-1 exit)\" failed its `.timeLimit` — `Time limit was exceeded: 1800.000 seconds` at `ElevationTests.swift:29`, plus two `check.held` failures at `ScenarioRunner.swift:805`. The scenario record shows a hang, not a slow pass: `RESULT [elevationInCodeMode] elapsed=1793.2s toolCalls=0 toolOutputs=0 pendingEnvelopes=0 reply=\"\"`. The model produced nothing for 30 minutes. The same suite passed on this dev box in 51.79s (card `^dwzkfzx`, 2026-08-19), and every other suite in the same CI run passed — 62 tests in 11 suites, 3 issues, all from this one scenario. The reworked in-band collection canary passed on CI in the same run.

## What

Find and remove the cause of the zero-activity hang. Known facts to start from:
- `toolCalls=0` means the turn hung before the first tool call — in generation, in model load, or in a gate — not in the deep-scan fixture (its delay is 8s) and not in `wait`.
- CI is uniformly ~6x slower than the dev box, which predicts ~5–6 minutes for this suite, not 30.
- The suites run `--no-parallel`, so nothing else held the resident profile during the run.
- The suite name still says \"Gated\" — rename it while in the file (see `^820xc9z` vocabulary rules).

Investigate the Router transcript for the run if CI kept one, or reproduce locally under memory pressure. Fix the failure class structurally — no retry, no time-limit raise (see `^nhxj8hx`'s ceiling-derivation method if the limit itself proves wrong after the hang is fixed).

## Acceptance Criteria

- [ ] The cause of the zero-activity hang is named on this card with evidence — still investigating. A first hypothesis (Router's `^1zt7vyg` generationGate/container-sharing defect) was raised and then REFUTED with direct evidence (see comments): `^1zt7vyg`'s fix (`14dd016`/`8db8094`) is an ancestor of the pinned Router revision `0f4b274` CI actually ran, confirmed via `git merge-base --is-ancestor`; and its defect requires a tool call already in flight, which never happened here (`toolCalls=0`). Follow-up investigation (Router's own `GenerationStall` semantics, suite-trait/complexity comparison against neighboring suites, fixture-caching check) ruled out cold model-load time, tool-surface-shape differences, and a too-tight `.timeLimit` ceiling as explanations, and confirmed the hang is inside the backend's actual generation call (dispatched correctly, not stuck in this repo's or Router's setup code) — but did not pin a cause. No conclusive cause is named yet.
- [ ] The fix is structural — no retry loop, no raised limit to mask the hang — no fix was applied; no structural cause has been pinned in this repo's own code, and no retry/limit-raise was added either.
- [x] The suite name no longer says \"Gated\" — `ElevationTests.swift`'s `@Suite` name and leading doc comment renamed; file greps clean of `[Gg]ated`.

## Tests

- [ ] `swift test --package-path IntegrationTests --no-parallel --filter Elevation` green locally, time recorded here — not run, per explicit instruction not to run the real-model suite (30+ minutes, scheduled separately by the orchestrator).
- [ ] A green CI integration job containing this suite, run id and suite time recorded here — not run this pass; orchestrator schedules CI runs separately.

Verified instead, per this pass's actual scope: `swift build --package-path IntegrationTests --build-tests` clean (\"Build complete! (5.58 sec)\"), and root `swift test` green (\"Test run with 367 tests in 32 suites passed after 5.492 seconds\").

## Workflow

- Use `/tdd` where a regression test can hold the cause; a hang found in fixture or harness code gets a failing test first.
