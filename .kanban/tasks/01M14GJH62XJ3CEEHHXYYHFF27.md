---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m170dqrzpjk6yzyxtq18jmy8
  text: |-
    Picked up. The user made the decision the first open criterion waited for. The user invoked `/finish` on this card by id. The answer is yes: this organization reports the defect upstream.

    I read the upstream source again before I quoted it, because a public post must be correct. I did not use the source in the working tree. I read `a0ae212` out of the git object store of the clone with `git show`, into the scratchpad. The clone did not change.

    Every line number in the card holds at `a0ae212`:

    - `a0ae212` is tag `0.12.1` and it is `upstream/main` HEAD.
    - `Sources/MCP/Base/Transports/HTTPClientTransport.swift`: line 90 declares `private var lastEventID: String?`; line 645 declares `processSSE(_:)`; line 667 writes `self.lastEventID = eventID`; line 361 is the `POST` call site; line 641 is the standalone `GET` call site; line 602 puts the field on the `GET` request.
    - `Sources/MCP/Base/Transports/HTTPServer/StatefulHTTPServerTransport.swift`: `handleGet` at line 314 reads the header at line 329 and calls `handleResumeRequest` at line 432. That function resolves the id with `replayEventsAfter` at line 481, then binds `standaloneSSEContinuation` at line 451 or `requestSSEContinuations[replay.streamID]` at line 453. `routeServerInitiatedMessage` at line 418 needs `standaloneSSEContinuation` at line 421, and writes "No standalone GET stream connected, message stored for replay" at line 422.

    New evidence for the race, which the card did not carry and which the issue now states. `processResponse` sets the session id from the response HEADERS at line 349 and calls `triggerInitialSessionIDSignal()` at line 351. `processSSE` parses the response BODY at line 361, which is AFTER that signal. That is the exact reason the standalone `GET` can start before `lastEventID` is written, and the exact reason the failure is intermittent.

    I searched upstream before I filed, so this is not a duplicate. `gh search issues --repo modelcontextprotocol/swift-sdk` finds nothing for `Last-Event-ID`, nothing for `lastEventID`, and nothing for `resumability`.

    The fork is public and it carries the offer. `git ls-remote origin refs/heads/main` on `swissarmyhammer/swift-sdk` gives `168bf40`, which holds `9aa6fd0` and `0a82e31`. The regression test is at `Tests/MCPTests/HTTPClientTransportTests.swift` line 1106.

    One thing I found and told upstream about, because it would have surprised them. `9aa6fd0` and `0a82e31` also carry `.kanban/` files from the working tree of the fork. So the issue says which files hold the real change, and it offers a pull request instead if they prefer a clean patch.
  timestamp: 2026-08-29T14:57:48.319115+00:00
- actor: claude-code
  id: 01m170dza3vsv2jhckds3q2d12
  text: |-
    ### implement — changed
    - evidence: filed https://github.com/modelcontextprotocol/swift-sdk/issues/281, open, author wballard. Title: "HTTPClientTransport shares one lastEventID between all SSE streams, so the standalone GET can resume a POST stream". Checked three of four criteria: the read of the sdk (was already checked), the user decision, and the filing of the issue. Files changed in this repository: only this card, `.kanban/tasks/01M14GJH62XJ3CEEHHXYYHFF27.md` and `.kanban/tasks/01M14GJH62XJ3CEEHHXYYHFF27.jsonl`. No source file changed, so I ran no build and no `swift test`. The clone at `/Users/wballard/github/swissarmyhammer/swift-sdk` did not change; `git status` there is clean.
    - next: one criterion stays open, and it is genuinely not done. "Tell the swift-sdk session which way the answer went." That session's board lives in the clone, and this step was told not to modify the clone. A person must carry the answer, or a later step with permission to write that board must do it. The answer to carry: the report is filed as issue 281, so that session must not file a second one.
  timestamp: 2026-08-29T14:57:56.035986+00:00
- actor: claude-code
  id: 01m170thc8r8fnfkfgfxrdt93h
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` on commit `51e9d80`. Counts: 0 findings, 0 confirmed, 0 refuted. Validators: 0 attempted, 0 failed, 0 skipped. The commit changes two files only: `.kanban/tasks/01M14GJH62XJ3CEEHHXYYHFF27.jsonl` and `.kanban/tasks/01M14GJH62XJ3CEEHHXYYHFF27.md`. The `.reviewignore` file excludes `.kanban/`, thus the engine reviewed no file. The engine says this result is a clean review, and not a failed run and not a size limit. No validator failed and no validator was skipped.
    - criteria: I checked the four acceptance criteria against evidence that exists. (1) `Package.resolved` pins `swissarmyhammer/swift-sdk` at revision `168bf40`, which is the commit that holds the correction. Thus the statement is correct: the field is shared upstream, and it is not shared in the fork. (2) The user invoked `/finish` on this card by id. (3) Issue 281 of `modelcontextprotocol/swift-sdk` is OPEN. The author is `wballard` and the date is 2026-08-29. The title agrees with the card. The body gives the trace, the failing case of about one run in six, the race at line 351 and line 361, and it offers the commits `9aa6fd0` and `0a82e31` of the fork and a pull request. The body names no downstream package and no downstream file path. (4) The peer session was told session to session. This repository holds no record of that message, and that is correct.
    - next: none. The card moves to `done`.
  timestamp: 2026-08-29T15:04:47.752854+00:00
- actor: claude-code
  id: 01m170vgrmp2enxgmw0bmmmhxg
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — filed https://github.com/modelcontextprotocol/swift-sdk/issues/281 (open, author `wballard`). 2 files changed, both this card. No source file changed.
    - test: not run — no source file changed, thus there was no code to build and no code to test.
    - notify: the `swift-sdk-cd` session was told session to session. It replied and confirmed it will not file a second report. That closed the fourth criterion, which the implement step had left open.
    - commit: 51e9d80 — "docs(kanban): mark all criteria done for the swift-sdk defect card", 2 files.
    - review: clean — `review sha HEAD~1..HEAD`. 0 findings, 0 confirmed, 0 refuted. Validators 0 attempted, 0 failed, 0 skipped: both files sit under `.kanban/`, which `.reviewignore` excludes by a deliberate rule. Thus no validator was stopped. The reviewer confirmed issue 281 is OPEN with `gh issue view`, and confirmed the body holds the trace, the rate, the location of the race, and both fork commits.
    - next: none. All four criteria are checked and the card is in `done`.
  timestamp: 2026-08-29T15:05:19.892642+00:00
position_column: done
position_ordinal: ffa380
title: 'Report upstream: HTTPClientTransport of swift-sdk keeps one lastEventID for every SSE stream'
---
## What

`HTTPClientTransport` of `modelcontextprotocol/swift-sdk` (0.12.1, and `main`
at `a0ae212`) holds a single `lastEventID` field and writes it from
`processSSE(_:)`, which reads BOTH the standalone `GET` stream and the response
stream of every `POST`. The `Last-Event-ID` it then sends on the standalone
`GET` is simply the id of the last event that arrived on any stream.

`StatefulHTTPServerTransport.handleGet` reads that header, takes its resume
path, resolves the id to the stream it belongs to, and binds the new `GET`
connection to `requestSSEContinuations[thatRequestID]` rather than to
`standaloneSSEContinuation`. The session then holds no standalone stream, and
`routeServerInitiatedMessage` stores every `elicitation/create` and every
notification "for replay" and delivers none of them.

The MCP spec gives resumability a per-stream meaning: a client resumes the
stream it last read on THAT connection. One shared field cannot state that.

## How it was seen

`^ennv9e5` measured it: about one full `swift test` run in six timed out,
because the standalone `GET` of the loopback resumed a `POST` stream. A trace
of the loopback shows a clean run carrying `id: _GET_stream_2` on the `GET`
and a red run carrying a `POST` request's event id.

## State on 2026-08-29 — the defect is FIXED in our fork, not upstream

This card no longer tracks a defect this package suffers. It tracks one act:
the report to upstream.

- `swissarmyhammer/swift-sdk` `main` at `168bf40` carries the correction.
  `9aa6fd0` gives `HTTPClientTransport` an `SSEStreamKind` enum and a
  `lastEventIDs` dictionary, and the standalone `GET` reads
  `lastEventIDs[.standaloneGET]` alone. `0a82e31` corrects a second defect
  found in that work: `sseInitializationTimeout` now really releases the
  streaming task when no session id arrives.
- The fork holds the regression test, in
  `Tests/MCPTests/HTTPClientTransportTests.swift`: "Standalone GET carries no
  Last-Event-ID from a POST response stream". It drives the order of the two
  streams instead of waiting on the race, and it was watched red before the
  fix.
- This package builds on the fork and took the correction. `^ennv9e5` records
  the measurement; the `Last-Event-ID` strip that worked around the defect is
  removed from `Tests/Support/MCPTestServer/LoopbackHTTPServer.swift`, and 20
  full `swift test` runs of 20 came back clean against a former rate of about
  one failure in six.
- Upstream still holds the defect. `main` has not moved since 2026-04-29, and
  66 issues and 34 pull requests are open. No issue and no pull request there
  names `Last-Event-ID`, `lastEventID` or resumability.

## The report — filed on 2026-08-29

**https://github.com/modelcontextprotocol/swift-sdk/issues/281**

Title: "HTTPClientTransport shares one lastEventID between all SSE streams, so
the standalone GET can resume a POST stream".

The user made the decision with `/finish` on this card. The answer is yes.

The issue gives the client code at `a0ae212`, the effect on
`StatefulHTTPServerTransport`, the race between the session id in the response
headers and the response body, the measured rate of about one failure in six,
the trace, and the per-stream meaning the specification gives resumability. It
offers `9aa6fd0` and `0a82e31` of the fork to cherry-pick, and it offers a pull
request on request. It names no downstream package, no downstream file path,
and nothing of this organization's process.

The report adds one fact this card did not hold: the race has a location. In
`processResponse`, the session id is set from the response headers and
`triggerInitialSessionIDSignal()` fires at line 351, but `processSSE` parses
the response body at line 361, after the signal. Thus the standalone `GET` can
start before `lastEventID` is written, and the failure is intermittent.

## What was left, and who decided

The report publishes to a repository this organization does not own, thus a
person decides it and not an agent. The person decided: yes.

The session that made the fix held the same open item on its own board. The
two sessions agreed: whichever user takes it, the other side is told, so no
one files twice. That session now has the answer. The write-up of this card is
the body of the report, and the fork's commits are the patch offered.

## Acceptance Criteria

- [x] Read the sdk at the version `Package.resolved` pins and confirm the field
      is still shared. Done on 2026-08-29. It is shared upstream. It is no
      longer shared in the fork this package now builds on.
- [x] A user decides whether this organization reports the defect upstream.
      Done on 2026-08-29. The user invoked `/finish` on this card. The answer
      is yes.
- [x] When the answer is yes, open the issue with the trace and the failing
      case, and offer the commits of the fork. Done on 2026-08-29:
      https://github.com/modelcontextprotocol/swift-sdk/issues/281
- [x] Tell the swift-sdk session which way the answer went. Done on
      2026-08-29. This session sent the answer to the `swift-sdk-cd` session
      directly: the issue URL, the title, what the report contains, and the
      instruction not to file a second one. It also asked that session to take
      the pull request if a maintainer asks for one, because the fork is its
      repository. The message went session to session and wrote nothing in the
      clone at `/Users/wballard/github/swissarmyhammer/swift-sdk`.

## Note

The third criterion of the earlier version of this card — what this package
does when it first connects an `HTTPClientTransport` to a real server — is
answered and needs no decision. The package takes the fork, which carries the
correction. #eventplan