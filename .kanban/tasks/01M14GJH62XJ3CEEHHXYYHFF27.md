---
assignees:
- claude-code
position_column: todo
position_ordinal: '9780'
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

## What is left, and who decides

The report publishes to a repository this organization does not own, thus a
person decides it and not an agent. Two sessions have declined to file it for
that reason.

The session that made the fix holds the same open item on its own board. The
two sessions agreed: whichever user takes it, the other side is told, so no
one files twice. The write-up of this card is the body of the report, and the
fork's commits are the patch to offer.

## Acceptance Criteria

- [x] Read the sdk at the version `Package.resolved` pins and confirm the field
      is still shared. Done on 2026-08-29. It is shared upstream. It is no
      longer shared in the fork this package now builds on.
- [ ] A user decides whether this organization reports the defect upstream.
- [ ] When the answer is yes, open the issue with the trace and the failing
      case, and offer the commits of the fork.
- [ ] Tell the swift-sdk session which way the answer went.

## Note

The third criterion of the earlier version of this card — what this package
does when it first connects an `HTTPClientTransport` to a real server — is
answered and needs no decision. The package takes the fork, which carries the
correction.
#eventplan