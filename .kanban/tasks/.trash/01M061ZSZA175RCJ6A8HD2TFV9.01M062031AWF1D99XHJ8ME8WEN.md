---
assignees:
- claude-code
position_column: todo
position_ordinal: '8180'
title: MLXLanguageModel cannot be given an MTP drafter, so speculative decoding is unreachable from a FoundationModels host
---
Filed from the `FoundationModelsMultitool` session. Evidence and requirement only; the design is yours.

## What was tried

Pinned `mlx-community/Qwen3.8-27B-MTP-mxfp4` as the generation model for a gated real-model suite, to measure MTP speed and accuracy against `Qwen3.8-27B-mxfp4` and `Muse-Glimmer-30B-mxfp4`. Every scenario failed at resolution in about half a second:

    .unsupportedModelType("qwen3_5_mtp")

## Why that is correct behaviour, not a bug

`qwen3_5_mtp` is registered twice in this repository, and both registrations are drafter registrations:

    Libraries/MLXLLM/Qwen35TextMTPRegistration.swift:20-21
        await MTPDrafterTypeRegistry.shared.registerModelType("qwen3_5_mtp", ...)
    Libraries/MLXVLM/Qwen35VLMMTPRegistration.swift:23-24
        await MTPDrafterTypeRegistry.shared.registerModelType("qwen3_5_mtp", ...)

Never with the primary model-type registry. `MTPDrafterModel`'s own documentation says what it is — "Protocol for Multi-Token Prediction (MTP) speculative drafter models", with a `target` parameter documented as "The main language model this drafter is speculating for".

So the model was pinned wrongly on our side. An MTP repo is a draft model that runs beside a base model and proposes tokens the base verifies; the speed-up is a property of the pairing. Nothing here needs fixing for that.

## The actual gap

The pairing is not expressible from a `FoundationModels` host.

`MLXFoundationModels.MLXLanguageModel` is what a host builds a `LanguageModelSession` over — our CLI does exactly that, at `CLIRunner.makeMLXLanguageModel(for:)`, and the gated suite reuses that same production wiring. Its initializer takes `configuration`, `capabilities`, `weightsLocation` and `load`. There is no drafter parameter, and no speculative-decoding option anywhere in `Libraries/MLXFoundationModels`:

    rg 'drafter|draft|speculat' Libraries/MLXFoundationModels/*.swift
    (no matches)

`MTPSpeculativeTokenIterator`, `MTPDrafterModel` and `MTPDrafterTypeRegistry` all live in `MLXLMCommon`, one layer below what a FoundationModels host consumes. So the capability exists and is unreachable through the surface we use.

`FoundationModelsRouter` has the same gap on its side — its loader exposes no drafter either — so a fix here does not land end to end without a matching change there. That half is theirs; this card is only about whether `MLXLanguageModel` can express a drafter at all.

## What would settle it

Some way for a host constructing an `MLXLanguageModel` to name a drafter repo alongside the target, so `loadModelContainer` (or whatever it delegates to) can build the target, build the drafter from `MTPDrafterTypeRegistry`, and drive `MTPSpeculativeTokenIterator` instead of the plain iterator. The shape is yours to choose — a parameter, a configuration type, or an inferred pairing from repo naming.

## Why it is worth having

Unmeasurable today. That is the point of the card: MTP claims a decode speed-up, and this repository has the implementation, but no consumer above `MLXLMCommon` can turn it on, so the claim cannot be tested by anyone building on `MLXFoundationModels`.

If a host is already meant to reach it some other way, saying so closes this card and we will use that path instead.

## Measured context, for sizing only

On the same hardware, one full gated run each through `MLXLanguageModel`:

    Muse-Glimmer-30B-mxfp4     ~10-14 tokens/second, search-then-call x4 in 283-299s
    Qwen3.8-27B-mxfp4          faster per scenario, search-then-call x4 in 265.6s

Decode speed is the dominant cost in every scenario we run — tool work is about 3 seconds of a 300-second scenario — so a real MTP speed-up would matter more here than any other optimisation available.