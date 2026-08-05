---
assignees:
- claude-code
depends_on:
- 01KZ6N038H8VC4C5CXQXYKSGNS
position_column: todo
position_ordinal: '8380'
title: '[Router] SessionMailbox actor in Hosting/'
---
Repo: ../FoundationModelsRouter. Basis: eventplan.md §"Elevation: waitSeconds and the completion token" (mailbox paragraphs) and §"Consolidation of the siblings" ("Processes and tasks stay different kinds"; "The run plane and the content plane are different surfaces").

## What
Create `Sources/FoundationModelsRouter/Hosting/SessionMailbox.swift`: an actor with the same scope rule as `SessionOutbox` — one per session, a fork gets its own fresh one, never shared. It owns parked runs and pending elicitations.

Parked-run entry (keyed by `completionToken`, a ULID string that IS the run's event `correlationID` — reuse the ULID machinery behind `SessionOutbox.ItemID`): the op string, a run-kind discriminator (phase 1 ships `swiftTask`; the enum is the seam where `process` and `mcpRequest` land in phases 2/4), latest progress detail, the settling `Task` handle, and a canceler closure carrying the kind's own semantics (Swift task → cooperative cancellation; the honest-outcome distinction `OperationOutcome` already makes mandatory).

API surface:
- `park(...)` — register a detached run (called by ElevatingTool, next tasks).
- `status()` — snapshot of pending runs: token, op, latest progress. Run plane only: the mailbox carries envelopes and outcomes, never bulk output.
- `wait(completionToken:seconds:)` — await settlement with a deadline. Its result is the run's terminal event `detail` — the (already capped) output tail plus the run's identifier — never a capability's full store. This is the single `wait()` contract; the sandbox-globals and exit tasks use the same wording.
- `cancel(completionToken:)` — invoke the canceler, return the honest `OperationOutcome`; unknown token is a safe, reportable no-op.
- Pending-elicitation registry keyed by `elicitationId` (ULID, distinct from the run's `completionToken`), typed with `ElicitationRequest`/`ElicitationResponse` from the elicitation-envelope task: holds a `CheckedContinuation` for a form answer; URL-mode entries stay open past `accept` until `complete(elicitationId:)` arrives; unknown and already-completed ids are safe no-ops per the MCP spec.
- `sweep()` — deterministic session-teardown sweep: for each parked run, invoke its canceler with that kind's semantics, ensure exactly one terminal event is posted (journal complete before close — no orphans, no holes); reject all pending elicitations.

Teardown entry point (finding from double-check: no such hook exists today — `RoutedSessionActor` has only `deinit`, which cannot await an actor or journal events): add an explicit async teardown requirement to `RoutedSession` (e.g. `func close() async`), whose default implementation runs `mailbox.sweep()` and drains the resulting terminal events into the journal before returning. Name its call sites: host apps ending a conversation, `multitool-cli` teardown, and fork/restore paths that discard a session. Document on `deinit` that it cannot and does not run the sweep — an unclosed crashed session is the `.lost` restoration task's territory.

Wire the session: `RoutedSession` protocol gains `nonisolated var mailbox: SessionMailbox` alongside `outbox` (RoutedSession.swift:116), created fresh at the three sites that create a `SessionOutbox` today (RoutedLLM.swift:204, RoutedSession.swift:1904 fork, SessionTreeRestoration.swift:279).

## Acceptance Criteria
- [ ] One mailbox per session; a fork's mailbox is a distinct instance; restore creates fresh instances
- [ ] `park`/`status`/`wait`/`cancel` round-trip a fake parked Task; `cancel` returns the outcome the canceler reports, not a guess
- [ ] `wait()` on a run whose fake body produced large output returns a bounded result carrying the run identifier, not the full output
- [ ] `RoutedSession.close()` runs the sweep: every parked run cancelled cooperatively, exactly one terminal event each, journaled before `close()` returns — asserted through `close()`, not by calling `sweep()` directly
- [ ] Unknown `completionToken` / `elicitationId` operations are no-ops that report "unknown", never throw or crash
- [ ] `cd ../FoundationModelsRouter && swift test` green

## Tests
- [ ] New `Tests/FoundationModelsRouterTests/SessionMailboxTests.swift`: park/status/wait/cancel lifecycle; wait deadline elapse; bounded wait-result; cancel-while-waiting; `close()`-driven sweep with multiple parked runs asserting one terminal event each in the journal; fork gets fresh mailbox; unknown-id no-ops
- [ ] `cd ../FoundationModelsRouter && swift test --filter SessionMailbox` green, full suite green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #phase-1 #router-first