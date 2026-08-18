---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0b8h0sbcyvegdpjq1vctqsb
  text: |-
    ## Done — 28.1s to 8.4s, and the ceiling came down with it

    The probe now resolves `plumbingProbeProfile`, built over one new constant `plumbingProbeModel` = `mlx-community/Qwen3-1.7B-4bit`. Qwen3 rather than a smaller model of another family, so the chat/tool template shape stays the one the shipped pin exercises — the part of the path a probe should not vary by accident.

        before (17GB pin)   14.1s  14.8s  16.4s  25.8s  28.1s   limit 3 minutes
        after  (1.7B)       12.0s   9.2s   8.6s                 limit 1 minute

    ## Acceptance criteria, each against evidence

    **Resolves a small model and says it grades plumbing.** Both the suite's own doc comment and `plumbingProbeModel`'s carry the distinction. The suite's states the reason concretely: nothing here asserts the quality, grounding or even the content of the reply — the reply is printed and graded by nothing — so the model's whole job is to emit tokens and call the one tool mounted.

    **The limit is re-derived, not merely kept.** Three consecutive runs gave 12.0s, 9.2s, 8.6s whole-test with profile resolution included. Sixty seconds is five times the slowest, the same order of margin three minutes gave the old readings. The comment records the three numbers and the arithmetic, as it demands of anyone changing it.

    **It still fails on a real deadlock.** The detector is unchanged and untouched by the model swap: a park leaves `entered=[checkModelReadiness] returned=[]`, the `nestedGenerationReturned` check fails on it, and the outer turn unwinds only when the limit cancels it. The gate is per-container and per-`Router`, not per-model, so no model choice can make a held permit come back. The run confirms the instrument is still live on this model — `GATE permits=1 waiters=0` then `permits=0 waiters=0` still print, so the permit is still being taken and still being sampled. The tighter ceiling makes the detector sharper, not weaker: a park is reported in a minute instead of three.

    **Named in one place.** `plumbingProbeModel` is the single reference; `plumbingProbeProfile` is built from it. It is documented at length as **not** a second generation pin — `CLIRunner.generationModel` remains the only place this package names the model a host runs.

    **Every other gated suite left alone.** `LiveRouterFixture.resolve(_:)` and `withLiveRouterFixture(name:profile:)` take the profile as a *defaulted* parameter, so no other runner changed. The exclusion list is recorded where the next reader meets it, with the rule stated as plumbing versus intelligence: `SearchThenCallTests`, `ElevationTests`, `AsyncFanOutTests`, `RespondDrainTests` and `InBandCollectionCanaryTests` each assert a valid, fixture-grounded answer and so make a capability claim; `SelectionForkPerCallTests` is excluded separately because cache behaviour is architecture-specific.

    ## Tests

    - Ungated `swift test` — green, 59 tests / 11 suites.
    - Gated probe alone — 11.4s under the new 60s limit, `result=PASS nestedCallEntered=pass nestedGenerationReturned=pass`.
    - **Full gated suite — green, 59 tests / 11 suites, 907.0s.** Every scenario passed on the shipped pin, so the defaulted parameter did not leak: `singleCallWeather`, `composeChain`, `discoveryUnderDistractors`, `repairFromTripProneTool`, `fanOutOverTwoStockTools`, `elevationInCodeMode`, `inBandCollection` all `result=PASS`. The probe ran 8.4s in that run, `elapsed=5.2s`.

    One number needs care rather than a claim: the whole run went 1287.3s to 907.0s, and the probe accounts for only about 20s of that directly. The rest is residency — the run no longer loads and evicts a 17GB model in the middle — and neighbouring suite times move run to run anyway, so nothing beyond the probe's own figure is attributed here.
  timestamp: 2026-08-18T20:20:40.363620+00:00
position_column: done
position_ordinal: d080
title: The nested-generation probe asks a plumbing question with a 17GB model — a 1B model would answer it in seconds
---
From the `FoundationModelsRouter` session, whose user cut a 28-minute compaction check down to **4.1 seconds** by dropping two assumptions. The insight generalises and this card applies it here.

## What they did

Their gated compaction eval took 28 minutes and had spawned four cards, three of which existed only because the measurement could not measure. Their user asked why answering "does compaction work at all" cost 28 minutes. It did not have to:

- **The 18GB model was not required.** `mlx-community/Llama-3.2-1B-Instruct-4bit` at 680MB loads in 1.9s and answers the same question.
- **The answering turn proved nothing about the fold.** Every defect they chased was a question about the summary itself — does it exist, is it smaller, was the fold applied. One generation, no session, no resumed turn.

Result: one six-turn transcript folded through `Compactor.compact`, five assertions, 4.1s total including load, driven red first. Their whole suite is 18 seconds with it.

## The shape, stated generally

**An expensive end-to-end path standing in for a cheap invariant.** They named our canary as the same shape, and they are right about the class even where the canary itself is not the example.

## Where it applies here

`NestedGenerationProbeTests` is the clearest case in this target. It asks a **plumbing** question — does a nested generation on a shared resident container deadlock — and nothing about it needs a capable model. It exists because Router's `generationGate` held a permit across tool rounds; the model's job in it is to emit any tokens at all so a second generation is attempted. It runs `Qwen3.8-27B-mxfp4` to do that, and most of its 14-28s is weight loading.

A 1B model would answer the same question, and the probe would become cheap enough to run on every change to the discovery path rather than only inside a 17-minute suite.

## What does NOT move, and why the distinction matters

Do not sweep the whole suite into this. These grade **model behaviour**, and a small model would fail them for reasons that say nothing about the product:

- `SearchThenCall` x4, `Elevation`, `AsyncFanOut`, `RespondDrain` — each asserts a valid, fixture-grounded answer. That is a capability claim.
- `InBandCollectionCanary` — asserts the model spends a `wait` call and carries the value. `^wnfzwxg` turned on exactly which model produced which answer; a 1B model cannot stand in.
- `PrefixReuse` — architecture-specific cache behaviour; a different model measures a different thing. See `^akpzysf`, which is about that suite measuring nothing as it stands.

The test is whether the assertion is about **plumbing or intelligence**. Plumbing can use a small model. Intelligence cannot.

## Acceptance Criteria

- [ ] `NestedGenerationProbeTests` resolves a small model rather than the generation pin, and states in its own comment that it grades plumbing rather than capability
- [ ] Its time limit is re-derived from the resulting measurement, as its own comment already demands of anyone changing it
- [ ] It still fails on a real deadlock — verified by reasoning about what it asserts, since the deadlock is fixed and cannot be reproduced on demand
- [ ] The model it uses is named in one place, consistent with `CLIRunner.generationModel` being the single pin for the generation slot — a second model reference must not reintroduce the drift `^tkrdwb8` removed
- [ ] Every other gated suite is left alone, with the plumbing-versus-intelligence distinction recorded where the next reader will meet it

## Tests

- [ ] Ungated `swift test` green
- [ ] One gated run of the probe with the new model, its elapsed time recorded here
- [ ] The full gated suite still green, since the probe shares the profile turnstile with every other scenario