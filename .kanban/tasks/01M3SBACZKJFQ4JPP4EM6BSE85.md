---
comments:
- actor: claude-code
  id: 01m3sbrteb0v486yyy64p1wt21
  text: |-
    ### finish — skipped (not started)
    - reason: the package build fails now in dependency FoundationModelsMetadataRegistry (PooledTextEmbedding.swift:65:18, 'PooledEmbedder' has no member 'dimension'). No test can go green until registry card 01M3QMDGD8148YNDHWBB1YXAQ1 is done and pushed.
    - reason: the working tree holds uncommitted changes of ^vg37780. A `/commit` for this card would put those changes in the wrong commit.
    - next: when the registry card is pushed, finish ^vg37780 first, then run `/finish` for this card.
  timestamp: 2026-09-30T14:33:49.259121+00:00
position_column: todo
position_ordinal: '8380'
title: Adopt TelemetryCapture.LogRecord in place of InMemoryLogHandler.Entry
---
## What
FoundationModelsExtras changed `TelemetryCapture.Context.logRecords` (pushed as 42ca5b5, OTel F). It now gives `[TelemetryCapture.LogRecord]` with `level`, `message`, `error`, `metadata` and `label`, not `[InMemoryLogHandler.Entry]`. Each record carries the label of the logger that wrote it.

- Change each use of `InMemoryLogHandler.Entry` to `TelemetryCapture.LogRecord` in `Tests/FoundationModelsMultitoolTests/`: `CoreLogRecordTests.swift`, `Fixtures/LogReadbackFixtures.swift` (its `extension InMemoryLogHandler.Entry`), `MCPLogRecordTests.swift`, `CallSpanTests.swift`, `SurfaceRefresherTests.swift`.
- Where a test identifies the logger by other means, assert `record.label` too.
- `swift package update`, confirm Extras is 42ca5b5 or later; push to `origin main` when green.

## Acceptance Criteria
- [ ] No Multitool file names `InMemoryLogHandler.Entry`.
- [ ] Each log readback test that concerns one logger checks its label.
- [ ] CI is green on the pushed commit.

## Tests
- [ ] The five test files above compile and pass with the new type.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #otel