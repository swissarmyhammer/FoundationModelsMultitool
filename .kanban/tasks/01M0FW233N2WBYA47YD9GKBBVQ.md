---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0g1dtafg9tsgkx5ks14y122
  text: |-
    Picked up. Research done.

    Part 1 is complete already. A dedicated agent made the change in the sibling repository `swissarmyhammer/workflows` and pushed it. Evidence: commit `283418a` ("feat(swift-ci): upload the integration artifacts with integration-artifacts-path") is on `origin/main` there. It adds to `.github/workflows/swift-ci.yaml`:

    - the optional input `integration-artifacts-path` (`required: false`, `type: string`, `default: ""`), and
    - a final step in the `integration` job, `Upload the integration artifacts`, with `if: always() && inputs.integration-artifacts-path != ''`, `uses: actions/upload-artifact@v4`, `name: integration-artifacts`, `path: ${{ inputs.integration-artifacts-path }}`, `if-no-files-found: ignore`.

    A caller that does not set the input behaves as before, so the input is safe to pass.

    Scope of this card in this repository is part 2 only:
    - `.github/workflows/ci.yml` must pass `integration-artifacts-path: IntegrationTests/.build/recordings` in the existing call, in the style of the other inputs (a comment block, then the input).
    - `Tests/FoundationModelsMultitoolTests/CIWorkflowTests.swift` must pin the new input, in the shape of the tests that pin `integration-package-path` and `integration-no-parallel`. Those use the private static helper `workflowContainsLine(_:)`.

    The path value is correct: `LiveRouterFixture.recordingsRoot` builds `<IntegrationTests package>/.build/recordings`, and `RecordingsLocationTests` holds that location.

    No sibling repository file is edited from here. No gated integration run is started from this card.
  timestamp: 2026-08-20T16:52:47.567929+00:00
- actor: claude-code
  id: 01m0g1wamekzszxkrap0kghzjh
  text: |-
    Implementation landed, test-first.

    RED: I added `sharedCallNamesIntegrationArtifactsPath()` to `CIWorkflowTests` before I touched `ci.yml`. `swift test --filter CIWorkflowTests` gave 4 passes and 1 failure, with the correct cause: `Expectation failed: namesArtifactsPath` — the workflow did not have the line.

    GREEN: I added the input to the `with:` block of `.github/workflows/ci.yml`, in the style of the three inputs above it (a prose comment, then the input). The comment records why the upload is necessary, names `LiveRouterFixture.recordingsRoot` and `RecordingsLocationTests`, and names workflows commit `283418a`. Then the same command gave 5 passes.

    I also made the suite doc comment agree with the new pin: the list of inputs now includes "the artifacts path that keeps the recorded transcripts of a run".

    I ran no gated integration suite, and I set no `MULTITOOL_INTEGRATION` variable.

    Rules I checked the change against, before I report:
    - duplication: the new test body is one call to the shared `workflowContainsLine(_:)` helper and one `#expect`. The rule says the fix is to call the shared function from the changed code, and that a block with no logic cannot drift. The shared helper was already there, so the parameterization is done.
    - missing-docs-swift: `swiftlint missing_docs` reports `open` and `public` declarations only. The new `@Test func` is internal, so it needs no doc comment. The private helpers keep the doc comments they had.
    - no-commented-code: the new YAML block is English prose, which the rule exempts.
    - no-test-cheating: the `#expect` asserts the exact line, not "is not empty", and I watched it fail before it passed.
    - test-partitioning: the change adds no environment variable and no switch. It serves the rule instead, because CI must run each integration target and must keep what the run writes.
  timestamp: 2026-08-20T17:00:43.022060+00:00
- actor: claude-code
  id: 01m0g1whdz84rt7kppxq14g5af
  text: |-
    ### implement — changed
    - evidence: 2 files — `/Users/wballard/github/swissarmyhammer/FoundationModelsMultitool/.github/workflows/ci.yml`, `/Users/wballard/github/swissarmyhammer/FoundationModelsMultitool/Tests/FoundationModelsMultitoolTests/CIWorkflowTests.swift`. `swift test --filter CIWorkflowTests` RED first (4 passed, 1 failed on the missing input line), then GREEN (5 tests in 1 suite passed). Full root `swift test`: 368 tests in 32 suites passed, no failure and no warning. Part 1 evidence: workflows commit `283418a` on `origin/main` of `swissarmyhammer/workflows`.
    - next: review. Two acceptance boxes stay open — the CI run that shows the uploaded artifact, and the run id — because the orchestrator must push and read the run.
  timestamp: 2026-08-20T17:00:49.983584+00:00
- actor: claude-code
  id: 01m0g1z0f2m774827g525aq4pq
  text: |-
    ### test — green
    - evidence: `swift test` (root) — 368 tests, 32 suites, 0 failures. `swift build --package-path IntegrationTests --build-tests` — build complete, 0 errors. `swift test --package-path IntegrationTests --filter "ScenarioFailureModeTests|ScenarioGradingTests|ScenarioFixtureTests|RecordingsLocationTests"` — 53 tests, 4 suites, 0 failures.
    - The only warning text in any run is the known mlx-swift_Cmlx.bundle resource-bundle message on record on cards ^akpzysf, ^dwzkfzx, ^jjyqe1a. It is not a new problem.
    - No test failed. No test was skipped. No code change was needed.
    - next: ready for review.
  timestamp: 2026-08-20T17:02:10.914723+00:00
position_column: doing
position_ordinal: '8380'
title: Upload the integration recordings as a CI artifact
---
The integration harness now writes each Router recordings directory under `IntegrationTests/.build/recordings/` (card `^hht0009`, `LiveRouterFixture.recordingsRoot`, held by `RecordingsLocationTests`). The `RESOLVED` log line prints the directory of each resolution. CI does not upload the directory yet, so a CI hang still leaves no transcript a person can read after the run.

## What

Make CI keep the recordings. Two parts:

1. **Sibling repository `swissarmyhammer/workflows`** (do not edit it from this repository; route the work to its own agent or person — the repository has no kanban board): add an input to `.github/workflows/swift-ci.yaml`, for example `integration-artifacts-path`, and an `actions/upload-artifact` step in the integration job with `if: always()` after the test step, so a hung or failed run also uploads. The step uploads the path the input names.
2. **This repository**: pass the new input from `.github/workflows/ci.yml` with the value `IntegrationTests/.build/recordings`, and add the input to the pins in `Tests/FoundationModelsMultitoolTests/CIWorkflowTests.swift`. Do this only after part 1 is on the `main` branch of the workflows repository — a caller that passes an unknown input fails the workflow call.

## Acceptance Criteria

- [x] The shared `swift-ci.yaml` has the artifact input and the `if: always()` upload step (sibling change, tracked here for the wiring dependency). Done by a dedicated agent in `swissarmyhammer/workflows`. Evidence: commit `283418a` on `origin/main` of that repository adds the optional `integration-artifacts-path` input and the `Upload the integration artifacts` step (`if: always() && inputs.integration-artifacts-path != ''`, `actions/upload-artifact@v4`, `if-no-files-found: ignore`).
- [x] `ci.yml` in this repository passes the input with `IntegrationTests/.build/recordings`.
- [x] `CIWorkflowTests` pins the new input.
- [ ] A CI integration run shows the uploaded artifact; run id recorded here. Stays open until the orchestrator pushes and reads the run.

## Tests

- [x] Root `swift test` green (`CIWorkflowTests` covers the pin). 368 tests in 32 suites pass, with no failure and no warning.
- [ ] One CI run with the artifact present. Stays open until the orchestrator pushes and reads the run.