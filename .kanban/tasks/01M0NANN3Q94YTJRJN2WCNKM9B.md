---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0nhxhve6tj6622wnndwah58
  text: |
    ### correction — use `swift package resolve`, not `update`

    The `## Tests` section of this card says to run `swift package update` in the
    repository root and in `IntegrationTests/`. Do not do that.

    Measured on 2026-08-22 on task `^pfa3der`: `swift package update` at the
    repository root took 55 minutes. It re-resolves every dependency, the branch
    pins included (Router `main`, the registry `main`, `mlx-swift-lm` `stable`),
    and it then walks the nested `.build/index-build/checkouts` trees inside the
    checkouts. `swift package resolve` in `IntegrationTests/` did the same job in
    22 seconds.

    Run `swift package resolve` in both places before the gated run.
  timestamp: 2026-08-22T20:17:12.558410+00:00
depends_on:
- 01M0NAN7P3RFWAR33JF1HQ8XNY
position_column: todo
position_ordinal: 8f80
title: 'Gated integration test: a detached shell command through the elevation path'
---
## What

eventplan.md § "Phases", phase 2: *"Shell is the reference emitter. Its
detached commands prove the elevation path end to end."*

Add a gated integration test that runs a real model against a real shell
capability, on the shipped configuration.

- Add
  `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/ShellElevationTests.swift`.
- Build the `MultiTool` with `withShell()`, and mount it on a Router session.
  Test the shipped configuration. Never build a bare `LanguageModelSession`.
- The trajectory:
  1. The model calls `findAPIs` and finds `tools.shell.execute`.
  2. The model runs `runCode` with a snippet that starts a long command.
  3. The outer `runCode` run elevates past `waitSeconds`. It returns the
     pending envelope with a `completionToken`.
  4. `status()` lists the run.
  5. `tools.shell.getLines` reads the output of the live run.
  6. `cancel(completionToken)` reports `.stopped`, and the child is gone.
- Assert on the events: one `progress` event at elevation, and exactly one
  terminal event that carries the outcome and the run identifier.
- Follow the reliability rule of this repository. Pin the decoding. Do not add
  a retry gate and do not add a sampling gate. Fix a failure class in the
  structure.

## Acceptance Criteria

- [ ] The test file is in the gated integration suite.
- [ ] It runs `MultiTool` on a Router session, with `withShell()`.
- [ ] It asserts the pending envelope carries a `completionToken`.
- [ ] It asserts `status()` lists the parked shell run.
- [ ] It asserts `getLines` reads the live run under the same token.
- [ ] It asserts `cancel` reports `.stopped` and the child process is gone.
- [ ] It asserts exactly one terminal event for the run.

## Tests

- [ ] `cd IntegrationTests && swift test --filter ShellElevationTests` passes.
- [ ] Run the gated suite one at a time. Do not chain two multi-minute runs in
      one shell command.
- [ ] Run `swift package update` in the repository root and in
      `IntegrationTests/` before the gated run. The nested package resolves
      separately.
- [ ] Run `git status` before the gated run. Another session can hold a
      temporary pin in this tree.
- [ ] `swift test` in the repository root passes with no new failure.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #phase-2 #eventplan