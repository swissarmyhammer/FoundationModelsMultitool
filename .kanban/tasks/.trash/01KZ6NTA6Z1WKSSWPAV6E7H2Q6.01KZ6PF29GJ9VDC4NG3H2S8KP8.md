---
assignees:
- claude-code
depends_on: []
position_column: todo
position_ordinal: '9280'
title: '[Router] Carry live completionTokens across the compaction boundary'
---
Repo: ../FoundationModelsRouter. Basis: eventplan.md §"The sandbox globals": "Rediscovery of in-flight work after compaction belongs to the run plane. … Router's compaction boundary carries the live `completionTokens` … A post-compaction model reads its pending work from the boundary. Then it calls `status()`." Added by the plan double-check: this behavior was owned by no task in any phase, and phases 2–5 would never pick it up.

## What
Research note: eventplan's analogy ("in the same way that boundary metadata keeps discovered-tool state") is aspirational — `Compaction/CompactionSegment.swift`'s `Content { liveWindowEntryIds, foldedEntryIds, tokensBefore, tokensAfter, stagesApplied, promptName }` carries no tool state of any kind today. This task creates the first such carrier.

- Add a field to `CompactionSegment.Content` (Codable; decode with `decodeIfPresent` so previously recorded segments load unchanged), e.g. `pendingRuns: [PendingRunSummary]?` with token, op, and latest progress detail per live parked run — read from the session's `SessionMailbox` at the moment the compaction boundary is written.
- On the post-compaction side, the boundary's pending-run summaries must be visible to the model the same way other boundary metadata is (in the compacted-transcript rendering), so a post-compaction model knows its tokens and can call `status()` for the live view.
- Keep it run-plane only: token, op, progress — never output content.

## Acceptance Criteria
- [ ] Compacting a session that holds a parked run records that run's `completionToken`, op, and latest progress in the boundary segment
- [ ] A previously recorded `CompactionSegment` JSON without the new field still decodes (back-compat)
- [ ] The post-compaction rendered boundary carries the pending-run summary; a session with no parked runs adds nothing
- [ ] `cd ../FoundationModelsRouter && swift test` green

## Tests
- [ ] Extend Router's compaction tests (`Compaction/` suites, pattern from `CompactionRoundTripIntegrationTests`' hermetic siblings): compact-with-parked-run round trip; back-compat decode; empty-mailbox no-op
- [ ] `cd ../FoundationModelsRouter && swift test` green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #phase-1 #router-first