---
assignees:
- claude-code
position_column: todo
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

- [ ] The README names the model `CLIRunner.generationModel` names, or names none and points at that constant
- [ ] Ungated `swift test` green (documentation-only change)