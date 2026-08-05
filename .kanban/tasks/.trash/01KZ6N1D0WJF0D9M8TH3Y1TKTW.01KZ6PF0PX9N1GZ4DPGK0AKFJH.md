---
assignees:
- claude-code
depends_on: []
position_column: todo
position_ordinal: '8780'
title: '[Router] Register OperationEventSegment; manufacture .lost on restore'
---
Repo: ../FoundationModelsRouter. Basis: eventplan.md §"Elevation" crash-edge paragraph: "Restoration marks journaled runs that have no terminal event as `.lost`." Research found the prerequisite gap this task closes.

## What
- `Recording/CustomSegmentRegistry.swift`: `routerDefault` (lines 168-172) registers only `CompactionSegment` today, so every default-argument restore path (`restoreSessionTree`, `effectiveTranscript(forSession:registry:)`, `RoutedModel.makeLanguageModel(resuming:registry:)`) throws `unregisteredCustomSegmentType` on any transcript containing a recorded operation event. Add `OperationEventSegment` to `routerDefault` and fix the doc at `Session/OperationEventSegment.swift:25-26` that currently assigns registration to the integrator.
- `Recording/SessionTreeRestoration.swift`: in the per-node `restore(_ node:)` closure (lines 250-320), scan the node's effective event stream for journaled runs that have a non-terminal event (`.progress` or elicitation kind) with no matching `.completed` for the same `correlationID`. For each, manufacture a terminal `.completed` event with outcome `.lost` and post it to the restored session's outbox, so the durable record has no holes and the model learns the run died with the crashed process. This is the only place `.lost` is manufactured outside an MCP transport drop.
- The teardown sweep (SessionMailbox task) handles the orderly-shutdown case; this task covers only the crash edge where the memory-only mailbox is gone.

## Acceptance Criteria
- [ ] Restoring a recorded transcript that contains `OperationEventSegment`s succeeds with the default registry (regression for the `unregisteredCustomSegmentType` throw)
- [ ] Restoring a transcript whose last events include a `.progress` with no matching `.completed` produces exactly one manufactured `.completed` with outcome `.lost` for that `correlationID`, delivered via the restored session's outbox
- [ ] A transcript whose runs all completed produces no manufactured events
- [ ] `cd ../FoundationModelsRouter && swift test` green

## Tests
- [ ] Extend `Tests/FoundationModelsRouterTests/` restoration coverage (pattern from `SessionTreeRestorationToolWiringTests.swift`): default-registry round trip with event segments; orphaned-run → `.lost` manufacture; completed-run → no manufacture; two orphaned runs → two `.lost` events with distinct correlationIDs
- [ ] `cd ../FoundationModelsRouter && swift test` green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #phase-1 #router-first