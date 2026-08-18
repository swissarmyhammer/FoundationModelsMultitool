---
assignees:
- claude-code
position_column: todo
position_ordinal: '8180'
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

## Acceptance Criteria

- [ ] The suite either asserts something only genuine prefix reuse can satisfy, or states plainly in its own documentation what it cannot see
- [ ] The name and doc comment match what it actually establishes — no "pin" over a timing comparison that warm-up satisfies
- [ ] Whatever it can no longer claim is removed from `IntegrationGate.swift`'s model-history prose, so no future model choice is justified by it
- [ ] `mlx-swift-lm`'s `f85fc50` is named as the rigorous instrument, so the next reader knows where the real measurement lives

## Tests

- [ ] Ungated `swift test` green
- [ ] One gated run of the suite, with the numbers recorded on this card — including `tokensIn` for both calls if the new assertion uses them