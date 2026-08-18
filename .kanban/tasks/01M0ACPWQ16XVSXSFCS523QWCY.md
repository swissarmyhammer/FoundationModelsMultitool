---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0anpk4mn3s5rf56ag6d4t0g
  text: |-
    Closed as part of one sweep over `^yzhpjab`, `^523qwcy` and `^mxjt7y5`.

    `README.md` now names **no** model and points at the constant instead: the paragraph says the demo pins one natively tool-calling-trained model on both slots, that the package names one in exactly one place (`CLIRunner.generationModel`, linked), that the gated suite resolves that same profile so a swap moves both, and that the measurement history lives beside the suite in `IntegrationGate.swift`. It also drops the old rationale sentence — "the router loads the weights once and both slots share them" read as a benefit, where `CLIRunner.demoProfile` records one resident container as a Router defect that used to deadlock, now fixed on their `^1zt7vyg`.

    `IntegrationGate.swift` carried the same class of error and was swept too:

    - "**Muse Glimmer replaces the Qwen pair.** Both generation slots now name `Muse-Glimmer-30B-mxfp4`" — present tense, false since `1344a51`. Now past tense, as the history it is.
    - The paragraph beginning "It is a vision-language model driven text-only here" read as describing the current pin. Now names Muse Glimmer explicitly, in the past, and states separately that the `MLXVLM` link and import are still needed for any pin with the same property.
    - The Qwen3.8-versus-Muse comparison never said which model won the slot. It now closes: which of the two holds it is stated in one place only, `CLIRunner.generationModel`; the section is the evidence, never a second pin.

    Two other files name a model and were **left alone on purpose**, because each is a dated measurement of a run that really happened on that model: `NestedGenerationProbeTests` ("Measured 2026-08-16, both slots pinned to Muse-Glimmer-30B-4bit"), `ScenarioRunner`'s recorded first-run block, `InBandCollectionCanaryTests`, `SelectionForkPerCallTests`, and `eventplan.md`'s 2026-08-04 propagation probe. `ScenarioTools.swift`'s nested-generation token limit did justify a *current* constant by naming Muse Glimmer, and was recast: the cap exists for any model that reasons before it answers, with Muse named as the one that held the slot when it was measured.

    ### implement — changed
    - evidence: `swift test` green — 359 tests in 30 suites, 59 tests in 11 suites. README.md, Tests/FoundationModelsMultitoolIntegrationTests/Support/IntegrationGate.swift, Tests/FoundationModelsMultitoolIntegrationTests/Fixtures/ScenarioTools.swift
    - next: review
  timestamp: 2026-08-18T14:51:40.052189+00:00
position_column: doing
position_ordinal: '8480'
title: README names a model the CLI does not pin
---
`README.md` states:

    The demo pins one natively tool-calling-trained model,
    `mlx-community/Muse-Glimmer-30B-4bit`, on both `standard` (the main session)
    and `flash` (`searchTools`'s selection tier)

`CLIRunner.generationModel` — the single place this package names a generation model — is `mlx-community/Qwen3.8-27B-mxfp4`. The two slot claim is still true; the model name is not.

Found while working `^260yggp`, which rewrote the surrounding section and deliberately left this line alone: a model name is a separate decision from the host-contract wiring that card was about.

## What to check

`IntegrationGate.swift` carries the measurement history for every model that has held the slot, including the Muse-to-Qwen3.8 comparison. Read it before writing the replacement sentence, so the README states what was measured rather than a new claim.

## Acceptance Criteria

- [x] The README names the model `CLIRunner.generationModel` names, or names none and points at that constant
- [x] Ungated `swift test` green (documentation-only change)