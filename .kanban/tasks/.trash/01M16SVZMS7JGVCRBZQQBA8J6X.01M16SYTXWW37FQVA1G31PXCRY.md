---
assignees:
- claude-code
position_column: todo
position_ordinal: 9a80
title: 'swift-sdk fork: give HTTPClientTransport a per-stream lastEventID'
---
## Where the work happens

NOT in this repository. The work is in the fork
`swissarmyhammer/swift-sdk`, cloned at
`/Users/wballard/github/swissarmyhammer/swift-sdk`. That clone has `origin`
on the fork and `upstream` on `modelcontextprotocol/swift-sdk`, and it sits
on `a0ae212`, which is `main`, tag `0.12.1`, and the revision this package
pins.

This card holds no `.kanban` board of its own, so the card stands here where
the diagnosis stands (`^ennv9e5`, `^yyhff27`). Keep the fork clean of board
files, because the fix should go upstream as a pull request later.

## The defect

`Sources/MCP/Base/Transports/HTTPClientTransport.swift` holds ONE event id
for every SSE stream:

    90:    private var lastEventID: String?

`processSSE(_:)` (line 645) writes that one field at line 667:

    if let eventID = event.id, !eventID.isEmpty {
        self.lastEventID = eventID
    }

and `processSSE` reads TWO different kinds of stream:

- line 361, the response stream of a `POST`
  (`let hadData = try await self.processSSE(stream)`);
- line 641, the standalone `GET` stream
  (`try await self.processSSE(stream)`).

The standalone `GET` then stamps that one field on itself at line 602:

    if let lastEventID = lastEventID {
        request.addValue(lastEventID, forHTTPHeaderField: HTTPHeaderName.lastEventID)
    }

So the `Last-Event-ID` of the `GET` is the id of the last event that arrived
on ANY stream, and usually that is a `POST` response stream.

## What it does to a server

`StatefulHTTPServerTransport.handleGet` reads the header, takes its resume
path, resolves the id to the stream that owns it, and binds the new `GET` to
`requestSSEContinuations[thatRequestID]` and not to
`standaloneSSEContinuation`. The session then holds no standalone stream, and
`routeServerInitiatedMessage` stores every `elicitation/create` and every
notification "for replay" and delivers none of them.

It is a race, and that is why it is intermittent. The `GET` goes out as soon
as the session id is read from the initialize response HEADERS, while that
response BODY is still parsing into `lastEventID`. Win the race and the field
is empty and the `GET` is clean; lose it and the `GET` carries a `POST`
stream's id.

The MCP spec gives resumability a per-stream meaning: a client resumes the
stream it last read on THAT connection. One shared field cannot state that.

## What to build

Make the id per-stream, and make the standalone `GET` read only the id of the
standalone stream.

- Give `processSSE(_:)` a parameter that says which stream it reads, or split
  the write so each caller stores into its own slot. The two call sites are
  line 361 (POST response) and line 641 (standalone GET).
- The read at line 602 must take the standalone stream's id alone. An id from
  a `POST` response stream must never reach that header.
- Keep the `POST` path storing its own id, because a `POST` response stream
  is resumable in its own right by the same spec.

## Acceptance Criteria

- [ ] `HTTPClientTransport` holds no single shared `lastEventID`.
- [ ] The standalone `GET` carries the id of the standalone stream, or no
      `Last-Event-ID` at all when that stream has read no event yet.
- [ ] A `POST` response stream's event id never reaches the `GET` header.
- [ ] `swift test` of the fork passes.

## Tests

- [ ] A test in the fork that drives a `POST` whose response stream carries an
      event id, then opens the standalone `GET`, and asserts the `GET` carries
      no `Last-Event-ID` of that `POST` stream. `MockURLProtocol` in the fork's
      own test target is the seam; this package's `LoopbackHTTPServer` shows
      the same shape.
- [ ] Watch it fail before the fix. The race makes an unguarded test pass by
      luck, so drive the ordering rather than waiting on it.

## After the fix lands in the fork

- [ ] Re-point this package at the fixed revision — see the sibling card for
      the dependency switch — and take the `Last-Event-ID` strip out of
      `Tests/Support/MCPTestServer/LoopbackHTTPServer.swift`, which exists
      only to work around this defect. `^ennv9e5` records that strip.
- [ ] Offer the fix upstream. `^yyhff27` holds the report, and upstream is
      close to dormant: `main` has not moved since 2026-04-29, with 66 open
      issues and 34 open pull requests.

## Workflow
- Use `/tdd` — write the failing test first, then the fix. #eventplan #swift-sdk-fork