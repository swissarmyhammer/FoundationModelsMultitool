---
assignees:
- claude-code
depends_on:
- 01KZ6N4Q7K53WSTJ3M6E76ZK99
- 01KZ6N545VYCB60H716AZ1XS92
- 01KZ6N5E30H5AQWS24E6VMK88B
- 01KZ6NSZAGGYJ9Z3A2YWPQ0Q6D
- 01KZBTW6RPCKT1BY8H3XX5ATMS
position_column: todo
position_ordinal: '9080'
title: '[Both] Phase-1 exit: gated end-to-end elevation scenarios; tag consolidation-1-foundation'
---
CROSS-BOARD PREREQUISITES (check before running; these live on sibling boards because the sah review tool is workspace-bound and cannot review sibling-repo commits):
1. The entire `router-first` batch on ../FoundationModelsRouter's kanban board is DONE (verified 2026-08-05, Router main f3bd00c pushed).
2. ../FoundationModelsOperationTool's board card "Operations shim: review + close the Router-vocabulary typealias commit" (same ULID 01KZ8RKKEKTXCZ0NHFKPZSGVDE — implementation already committed there as 12530b4) must be DONE.
3. ../FoundationModelsShelltool's board card "Bump platform floor to macOS 27 to consume the Operations Router-vocabulary shim" (ULID 01KZ95SQNZ9KZVK1THDTP78XWH) must be DONE.
Do not tag with any of those still open.

Repos: this repo + ../FoundationModelsRouter + ../FoundationModelsOperationTool. Basis: eventplan.md §"Phases" phase 1 exit criteria.

## What
Close phase 1 with live proof and the tag:
- New gated scenarios in `Tests/FoundationModelsMultitoolIntegrationTests/` (gate `MULTITOOL_INTEGRATION`, pattern: `ScenarioRunner.runNativeIntegrationScenario` + `NativeTranscript`, fixtures in `Fixtures/ScenarioTools.swift`):
  1. Elevation in code mode: a slow fixture tool driven so the outer `runCode` elevates; the model receives the pending envelope, follows up with `status()`/`wait(completionToken)` — `wait()` returns the terminal event's `detail` (the capped output tail plus the run identifier), which is what the model answers from — and produces the final answer (outcome-over-path assertion on the answer plus a transcript check that a pending envelope appeared).
  2. Async fan-out: a prompt whose natural snippet uses `Promise.all` over two fixture tools; assert the correct combined answer.
  3. Trajectory gate stays green: the existing search-then-call scenarios (`SearchThenCallTests`) and `PrefixReuseTests` still pass — the description-text changes from the globals/envelope tasks must not regress the discipline.
- Router side: confirm the gated suite (`FM_ROUTER_INTEGRATION_TESTS`) is green including the turn-riding completion behavior added by the mount task and the propagation probe.
- Verify the exit criterion: `grep -r "import Operations" ../FoundationModelsRouter/Sources` empty (only the shim points the other way). The org-wide zero-imports check is phase 5's exit, not this one.
- Tag all three repos (Router, MultiTool, and OperationTool for the shim commit) `consolidation-1-foundation` and push tags.

Run gated suites one at a time, one shell command per run, and check `git status` for concurrent-session edits before each gated run.

## Acceptance Criteria
- [ ] Every `router-first` task on ../FoundationModelsRouter's kanban board is in `done`
- [ ] The OperationTool shim card and Shelltool platform-bump card (cross-board prerequisites above) are in `done` on their own boards
- [ ] `MULTITOOL_INTEGRATION=1 swift test` green in this repo including the three new/kept scenario groups
- [ ] `FM_ROUTER_INTEGRATION_TESTS=1 swift test` green in ../FoundationModelsRouter
- [ ] Ungated `swift test` green in this repo, Router, and OperationTool
- [ ] `consolidation-1-foundation` tag exists on the phase-1 commits of Router, MultiTool, and OperationTool

## Tests
- [ ] The gated scenarios above ARE the tests; commands: `MULTITOOL_INTEGRATION=1 swift test --filter Elevation` (new suite), then the full gated suite, then Router's — each as a single separate run
- [ ] `swift test` (ungated) in all three repos

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #phase-1