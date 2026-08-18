---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0afew7gdc2e2m39m05mzy0x
  text: |-
    Picked up. First gated probe run is done — one `--filter PrefixReuse --no-parallel` run with a temporary diagnostic that dumps every `.flash`-slot recorded event.

    ```
    RESULT [prefixReuse] first=6.518s second=4.135s
    PROBE seq=0 kind=session  session=01M0AFD0N829877J1G6BRKEP9S parent=01M0AFD0N79H5F4SWNAKBPMEX1 tokensIn=nil  tokensOut=nil ms=nil    textLen=-1
    PROBE seq=1 kind=prompt   session=01M0AFD0N829877J1G6BRKEP9S parent=01M0AFD0N79H5F4SWNAKBPMEX1 tokensIn=nil  tokensOut=nil ms=nil    textLen=41
    PROBE seq=2 kind=response session=01M0AFD0N829877J1G6BRKEP9S parent=01M0AFD0N79H5F4SWNAKBPMEX1 tokensIn=1144 tokensOut=14  ms=6513  textLen=-1
    PROBE seq=3 kind=session  session=01M0AFD70WD4QZ3PBSS6S13ARX parent=01M0AFD0N79H5F4SWNAKBPMEX1 tokensIn=nil  tokensOut=nil ms=nil    textLen=-1
    PROBE seq=4 kind=prompt   session=01M0AFD70WD4QZ3PBSS6S13ARX parent=01M0AFD0N79H5F4SWNAKBPMEX1 tokensIn=nil  tokensOut=nil ms=nil    textLen=22
    PROBE seq=5 kind=response session=01M0AFD70WD4QZ3PBSS6S13ARX parent=01M0AFD0N79H5F4SWNAKBPMEX1 tokensIn=1144 tokensOut=11  ms=4133  textLen=-1
    ```

    Two facts the run establishes:

    1. The `fork()`-per-call path is real and visible. Two distinct child session ids, both with the SAME parent id — one prefix-rooted root session, one fresh child per selection call. That is the mechanism the suite drives, and it is worth keeping.
    2. `tokensIn` is recorded, and it is 1144 on BOTH calls — identical, although the two prompts are different lengths (41 vs 22 characters, so a few tokens apart). A number that does not move with the prompt cannot report what a turn prefilled.

    Tracing what `usage.input` actually counts before deciding between the card's two resolutions.
  timestamp: 2026-08-18T13:02:35.760042+00:00
- actor: claude-code
  id: 01m0ah47v3y0ervywsjg93xxv6
  text: |-
    ## The decision: resolution 2, and the evidence that closes resolution 1

    `tokensIn` cannot distinguish a skipped prefill from a full re-prefill. Traced through the shipped build, not assumed:

    - `RoutedSessionActorTurnExecution` snapshots `backend.usageTokenCounts()` before the turn and after, and `RoutedSessionActorRecording.usageDelta(before:after:)` subtracts them. `LiveModelLoader.usageTokenCounts()` returns `(usage.input.totalTokenCount, usage.output.totalTokenCount)`.
    - `totalTokenCount` is the WHOLE rendered prompt. Upstream it is `GenerateCompletionInfo.promptTokenCount` = `inputText.tokens.size`. It counts the render whether or not a cached prefix was skipped.
    - The one figure that answers the question is `usage.input.cachedTokenCount`. `LiveModelLoader.usageTokenCounts()` reads only the two `totalTokenCount`s and **drops it**.
    - Worse: in the pinned `mlx-swift-lm` (`Package.resolved` → branch `stable`, `acc92059`) the FoundationModels executor carries **no prompt cache at all** — no `ExecutorPromptCache.swift`, no `ChatSession`/`trimToCommonPrefix`, and `cachedTokenCount: 0` is a hardcoded literal at all five `emitUsage` sites. Nothing is ever skipped on this path, so there is nothing for a count to report.
    - `TranscriptEvent` carries only `tokensIn`, `tokensOut`, `ms`. No skipped-token count, no cache-hit count, no prefill time.

    Surfacing `cachedTokenCount` would mean widening `LanguageModelSessionBackend.usageTokenCounts()` (one production conformer plus ~20 test stubs), `usageDelta`, `TranscriptEvent.Partial`, `SessionEvent.TokenUsage`, `SessionProjection` and `TokenBudget` — **and it would still read `0`** until the pin moves off `acc92059`. That is Router and upstream work, not this card.

    There is a second oddity the code does not explain, recorded so nobody chases it twice: both turns report exactly `tokensIn=1144`, across three separate runs, although the two intents tokenize 8 and 6 tokens under the model's own tokenizer. Every hop from `emitUsage` to the stamp is straight-line per-turn whole-render arithmetic, so the code predicts `X` and `X-2`. The discrepancy can only live in the closed FoundationModels hop between the executor's `updateUsage` event and `LanguageModelSession.usage`. Nothing asserts on that number.

    ## What landed

    `PrefixReuseTests.swift` → `SelectionForkPerCallTests.swift`, renamed and narrowed, not deleted. It now asserts the mechanism it actually drives, read off the recording:

    1. at least one recorded selection generation per `searchTools` call;
    2. at least one distinct child session per call — the second call forks its own, it does not reuse the first's;
    3. every generation names the root it was forked from;
    4. exactly ONE distinct root across the run — the cached root was not dropped and rebuilt.

    The timing check `second <= first` stays, stated as a warm-vs-cold timing check, with the doc saying in as many words that warm-up alone satisfies it and no reader should take it for reuse.

    Also corrected, so the doc no longer claims what the `fork()` does not do: `LiveModelLoader.makeFork(tools:)` builds a brand-new `LanguageModelSession` seeded from the parent's *transcript*. The child inherits history, not a prefilled KV cache — the old doc comment said KV cache.

    ## Gated runs

    Verification run, `--filter SelectionForkPerCall --no-parallel`:

    ```
    RESULT [selectionFork] first=5.858s second=3.590s children=2 roots=1
    RESULT [selectionFork] generation seq=2 tokensIn=1144(asserted on by nothing) tokensOut=14 ms=5854
    RESULT [selectionFork] generation seq=5 tokensIn=1144(asserted on by nothing) tokensOut=11 ms=3588
    ✔ 1 test in 1 suite passed after 13.420 seconds
    ```

    **Non-vacuity run.** The whole point of this card is that an assertion nobody watched fail is worthless, so all four new assertions were inverted and run gated. All four failed, each with the real observed number in its message:

    ```
    ✘ generations.count >= 3      — "but the .flash slot recorded 2"
    ✘ childSessionIds.count >= 3  — "but the run recorded 2"
    ✘ unforkedGenerationCount == 1 — "but 0 of 2 name no parent at all"
    ✘ rootSessionIds.count == 2   — "but the run recorded 1 distinct roots"
    ✘ 1 test in 1 suite failed with 4 issues
    ```

    Reverted, re-run, green.

    ## Prose corrected in `IntegrationGate.swift`

    - The Muse Glimmer paragraph no longer ends "so `PrefixReuseTests` had nothing left to measure". It now states plainly that no suite here ever graded the swap, and that the cache-shape argument rests on the two architectures and on `mlx-swift-lm`'s `f85fc50`.
    - The Qwen3.8 comparison paragraph gains the recorded-entries finding above.
    - The closing line no longer says "do not cite `PrefixReuseTests`"; it says no suite here can be cited, names `SelectionForkPerCallTests` as the least citable of all, and points at `f85fc50`.
    - The `--no-parallel` timing table row and the Qwen3.5-9B run record carry the new name.

    Stale names also fixed in `ScenarioRunner.swift`, `NativeTranscript.swift`, `SelectionGrammar.swift` and `plan.md` (whose "the gated `PrefixReuseTests` pins it" now says the suite holds the fork-per-call contract, and warns that no suite here can see whether a prefill was skipped). The three surviving mentions of the old name are deliberate — each says "it was called that" while correcting what it claimed.
  timestamp: 2026-08-18T13:31:44.355392+00:00
- actor: claude-code
  id: 01m0ah54s3hae01br2b6m7c2z1
  text: |-
    ### implement — changed
    - evidence: 7 files — Tests/FoundationModelsMultitoolIntegrationTests/SelectionForkPerCallTests.swift (new), Tests/FoundationModelsMultitoolIntegrationTests/PrefixReuseTests.swift (deleted), Tests/FoundationModelsMultitoolIntegrationTests/Support/IntegrationGate.swift, Tests/FoundationModelsMultitoolIntegrationTests/Support/NativeTranscript.swift, Tests/FoundationModelsMultitoolIntegrationTests/Support/ScenarioRunner.swift, Sources/FoundationModelsMultitool/Discovery/SelectionGrammar.swift, plan.md. Ungated `swift test`: 359 tests/30 suites and 59 tests/11 suites, zero failures, zero warnings. Gated `--filter SelectionForkPerCall --no-parallel`: 1 test/1 suite passed, `children=2 roots=1`, both turns `tokensIn=1144`. Non-vacuity run with all four assertions inverted: 4 issues, one per assertion.
    - next: ready for `/review`
  timestamp: 2026-08-18T13:32:13.987258+00:00
position_column: doing
position_ordinal: '8380'
title: PrefixReuseTests pins nothing — its assertion is satisfied by model warm-up alone
---
`PrefixReuseTests` is named a pin and asserts one thing:

    Tests/FoundationModelsMultitoolIntegrationTests/PrefixReuseTests.swift:96
        secondElapsed <= firstElapsed

Two `searchTools` calls are timed, and the second must not be slower than the first.

## Why that measures nothing

The first call pays model warm-up that the second never pays. That alone satisfies the assertion, with zero prefix reuse anywhere in the stack. A run where the second call re-prefilled the entire selection prefix from scratch would still pass, provided warm-up cost more than the re-prefill saved.

Measured on 2026-08-16, both models pass and neither passes decisively:

    Muse-Glimmer-30B-mxfp4   first=7.75s  second=3.31s
    Qwen3.8-27B-mxfp4        first=5.81s  second=3.58s

A second call that genuinely skipped a prefill and one that merely followed a warmed model produce the same verdict here.

## Why this matters more than a weak test usually would

The suite is cited as evidence. `IntegrationGate.swift` records that the pin moved to Muse Glimmer *because* Qwen3.5/3.6's non-trimmable `MambaCache` "left `PrefixReuseTests` nothing to measure" — a model choice justified by a suite that cannot measure the thing. The comment has since been corrected to say so, but the suite is still there under a name that claims otherwise.

The rigorous instrument exists and is not ours: `mlx-swift-lm`'s `f85fc50` measures two-round reuse on real weights through `MLXLMCommon.ChatSession`, comparing rendered token counts and prefill time against a cold control. Its verdict on Qwen3.6 was NO on two independent counts — the second render was not a prefix extension of the first (4,703 of 4,705 tokens shared and still not an extension, because round 1 ends with a `<think>` priming block where round 2 writes the reply), and round 2 fed all 4,748 tokens, skipped none, and spent 11.59s on prefill against a cold control's 11.60s.

So the honest state is: **we have no evidence prefix reuse works on any model we ship**, and a suite whose name implies we do.

## What a fix has to decide

Either make it measure, or stop claiming it does. Both are legitimate; guessing between them is not.

- **Make it measure.** The selection tier's sessions are Router-vended and therefore recorded. `tokensIn` on the second call's `response` entry, against the first's, is the number that says whether a prefill was skipped — the same arithmetic that established ~10-14 tokens a second elsewhere in this target. That is a real assertion and it needs no new machinery.
- **Or rename and narrow it.** If the recorded entries cannot distinguish reuse either, say so in the suite, assert only what the timings can support, and delete the word "pin". A test that honestly measures "the second call is not slower" is fine; one that implies it measured reuse is not.

Do not delete the suite to make the problem go away — the `fork()`-per-call path it drives is real and worth exercising even if the reuse claim goes.

## Resolved: the second branch, on measured evidence

`tokensIn` cannot distinguish a skipped prefill from a full re-prefill, so the first branch is closed. It is the whole rendered prompt of the turn (`usage.input.totalTokenCount`, upstream `promptTokenCount` = `inputText.tokens.size`), and it counts the render whether or not a prefix was skipped. The one figure that would answer the question, `usage.input.cachedTokenCount`, is dropped by `LiveModelLoader.usageTokenCounts()` — and in the pinned `mlx-swift-lm` (`acc92059`) the FoundationModels executor carries no prompt cache at all, so it is a hardcoded `0`. See the comment thread for the full trace and the gated numbers.

The suite is now `SelectionForkPerCallTests`. It asserts the cached-root, `fork()`-per-call contract off the recording, keeps the timing check stated as a timing check, and documents what it cannot see.

## Acceptance Criteria

- [x] The suite either asserts something only genuine prefix reuse can satisfy, or states plainly in its own documentation what it cannot see
- [x] The name and doc comment match what it actually establishes — no "pin" over a timing comparison that warm-up satisfies
- [x] Whatever it can no longer claim is removed from `IntegrationGate.swift`'s model-history prose, so no future model choice is justified by it
- [x] `mlx-swift-lm`'s `f85fc50` is named as the rigorous instrument, so the next reader knows where the real measurement lives

## Tests

- [x] Ungated `swift test` green — 359 tests/30 suites and 59 tests/11 suites
- [x] One gated run of the suite, with the numbers recorded on this card — including `tokensIn` for both calls if the new assertion uses them