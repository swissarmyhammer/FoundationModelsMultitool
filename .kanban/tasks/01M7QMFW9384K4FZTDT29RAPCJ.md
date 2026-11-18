---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m7qndsm6enhdq6p1fn6nte42
  text: 'Extras plan (from foundationmodelsextras-9e, 2026-11-18): the next Extras push adds `SessionDirectoryEvent.messageQueued(SessionMessage)`. Map it to `(message.to, .changed)` in the exhaustive switch at `SessionsGraphChanges.swift:52`; without it, Multitool does not compile. The same push makes the in-memory directory send `messageDelivered` for a queued message when its turn starts. Then `SessionsGraphChangesTests.swift:234` ("send to a working session") passes only with the `messageQueued` mapping. Multitool CI resolves the Extras main head, so Multitool main CI breaks from the Extras push until this task is on main: do this task at once when the sha comes.'
  timestamp: 2026-11-18T15:46:52.166330+00:00
- actor: claude-code
  id: 01m7qpkzeqtqynezqqgc2epkp9
  text: |-
    Implementation notes.
    - Extras pin: `swift package update FoundationModelsExtras` resolved main 951149ce8b2aa4e13025e3dbd72fb5fcc6cde37d. No other sibling moved.
    - RED: before the change, `swift build` failed with "switch must be exhaustive" at the `sessionChange` switch, because `messageQueued` had no mapping.
    - Change: `case .messageQueued(let message): (message.to, .changed)` in `SessionDirectoryEvent.sessionChange`. No `default:`. `messageDelivered` stays `changed`. The file header and the doc comment of `sessionChange` now tell that a waiting message changes its target at the send, and again when the target takes it.
    - Tests (SessionsGraphChangesTests): `aSendToAWaitingTargetGivesAChangeAtTheSend` (two cases: working target QUEUED, recorded target with isLive false SENT; each gives the target change before the marker change, and unreadCount 1), and `anExternalClientGetsTheWaitingMessageChangeOnlyWhenVisible`. The existing "send to a working session" action case passes with no change: it needs the `messageQueued` mapping now, because the target turn never ends in that case.
    - swift format sorted the imports (GraphQL before Graphiti), wrapped one long description line, and wrote `catch  where` with two spaces in `anchorChain(of:reading:)`. That is the output of the mandated format command; I did not edit it by hand.
  timestamp: 2026-11-18T16:07:43.319945+00:00
- actor: claude-code
  id: 01m7qpm2bxrwvsxctm10nhctqk
  text: |-
    ### implement — changed
    - evidence: 2 files — Sources/FoundationModelsMultitool/Capabilities/Sessions/SessionsGraphChanges.swift, Tests/FoundationModelsMultitoolTests/SessionsGraphChangesTests.swift. Pin: FoundationModelsExtras 951149ce (no other sibling moved). `swift build` complete; `swift test --filter "SessionsGraph|SessionsTool"`: 236 tests in 12 suites passed; full `swift test`: 3086 tests in 274 suites passed, 0 issues, 0 warnings. All 4 Tests boxes ticked.
    - next: /review
  timestamp: 2026-11-18T16:07:46.301641+00:00
- actor: claude-code
  id: 01m7qps839y91qj3ptpv2aekcd
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (39188c8b): 0 findings, 0 confirmed, 0 refuted; 7 validator runs, 0 failed. 2 files reviewed (SessionsGraphChanges.swift, SessionsGraphChangesTests.swift); 2 .kanban files ignored by .reviewignore.
    - `catch  where` (two spaces) in `anchorChain(of:reading:)`: no finding. swift format 6.4.4 writes two spaces for every `catch where` that has no pattern. A format of GitContext.swift to stdout also gives `catch  where`. Thus the text is stable formatter output, and the code compiles. The other `catch where` lines in Sources have one space only because their files did not go through the formatter again.
    - next: none. The task moves to done.
  timestamp: 2026-11-18T16:10:36.009841+00:00
- actor: claude-code
  id: 01m7qpssacmtk5k417g4w4731z
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — SessionsGraphChanges.swift (messageQueued → changed), SessionsGraphChangesTests.swift (2 new tests); local pin Extras 951149ce
    - test: green — swift test, 3086 passed (run in the implement step)
    - commit: 39188c8b (pushed before the review, because main did not compile against Extras 951149ce without it)
    - review: clean — 0 findings; `catch  where` with two spaces is the output of swift format 6.4.4
  timestamp: 2026-11-18T16:10:53.644769+00:00
position_column: done
position_ordinal: ffffffff9480
title: The change feed gives a changed entry when a message goes into the queue or the inbox of a target (D199)
---
Decision: D199 (f) in TestudoApp/features/decisions.md. Request from the TestudoApp session, 2026-11-18: choice (a), the fix at the source.

Precondition (FoundationModelsExtras and FoundationModelsRouter): a new directory event when a message goes into the ledger or the inbox of a target. TestudoApp asks Extras and the Router for it. Before you start, examine origin/main of ../FoundationModelsExtras and ../FoundationModelsRouter, and read the name and the payload of the new event.

## Current behavior

- `SessionsGraphChanges.swift:56` maps `messageDelivered` to a `changed` entry of the target.
- Router 709d82c5 (^jf3j3v5) sends `messageDelivered` when the target takes the message (for a queued message, when its turn starts), not at send time.
- The Router writes the ledger when the mail goes in the queue. Thus `Session.unreadCount` of the target grows at send time, but the `changed` entry comes later. A recorded target (inbox file, receipt `sent`) gives no entry until its next open or inbox read. A client of `changes(after:)` shows an old `unreadCount` in that time.

## Work

- Map the new event to a `changed` entry of the target in `SessionChange` (`SessionsGraphChanges.swift`), with the anchor chain of the target, as for the other events.
- Keep `messageDelivered` as a `changed` entry too.
- Update the doc comments of the change feed.

## Tests

- [x] A send to a working target gives a `changed` entry for the target at send time, and `unreadCount` is then 1.
- [x] A send to a recorded target (receipt `sent`) gives a `changed` entry for the target.
- [x] An external viewer gets the entry only for a session that it can see.
- [x] The test kit of the conventions (EXTRAS-11) stays green. #sessions #at-sessions #graphql