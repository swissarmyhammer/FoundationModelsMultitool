---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: Upload the integration recordings as a CI artifact
---
The integration harness now writes each Router recordings directory under `IntegrationTests/.build/recordings/` (card `^hht0009`, `LiveRouterFixture.recordingsRoot`, held by `RecordingsLocationTests`). The `RESOLVED` log line prints the directory of each resolution. CI does not upload the directory yet, so a CI hang still leaves no transcript a person can read after the run.

## What

Make CI keep the recordings. Two parts:

1. **Sibling repository `swissarmyhammer/workflows`** (do not edit it from this repository; route the work to its own agent or person — the repository has no kanban board): add an input to `.github/workflows/swift-ci.yaml`, for example `integration-artifacts-path`, and an `actions/upload-artifact` step in the integration job with `if: always()` after the test step, so a hung or failed run also uploads. The step uploads the path the input names.
2. **This repository**: pass the new input from `.github/workflows/ci.yml` with the value `IntegrationTests/.build/recordings`, and add the input to the pins in `Tests/FoundationModelsMultitoolTests/CIWorkflowTests.swift`. Do this only after part 1 is on the `main` branch of the workflows repository — a caller that passes an unknown input fails the workflow call.

## Acceptance Criteria

- [ ] The shared `swift-ci.yaml` has the artifact input and the `if: always()` upload step (sibling change, tracked here for the wiring dependency).
- [ ] `ci.yml` in this repository passes the input with `IntegrationTests/.build/recordings`.
- [ ] `CIWorkflowTests` pins the new input.
- [ ] A CI integration run shows the uploaded artifact; run id recorded here.

## Tests

- [ ] Root `swift test` green (`CIWorkflowTests` covers the pin).
- [ ] One CI run with the artifact present.