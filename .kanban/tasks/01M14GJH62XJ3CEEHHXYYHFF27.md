---
assignees:
- claude-code
position_column: todo
position_ordinal: '9780'
title: 'Report upstream: HTTPClientTransport of swift-sdk keeps one lastEventID for every SSE stream'
---
## What

`HTTPClientTransport` of `modelcontextprotocol/swift-sdk` (0.12.1) holds a
single `lastEventID` field and writes it from `processSSE(_:)`, which reads
BOTH the standalone `GET` stream and the response stream of every `POST`. The
`Last-Event-ID` it then sends on the standalone `GET` is simply the id of the
last event that arrived on any stream.

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

## Why this task stands

`^ennv9e5` repaired the SYMPTOM at the only seam this package owns:
`LoopbackHTTPServer.handle(_:)` drops `Last-Event-ID` before it routes, so the
loopback serves no resumption. That is correct for a same-process loopback
whose session never outlives a disconnect. It does nothing for a real
streamable-HTTP MCP server.

No production code of this package builds an `HTTPClientTransport` today, so
nothing shipped is exposed. A task that adds one would be.

## Acceptance Criteria

- [ ] Read the sdk at the version `Package.resolved` pins and confirm the field
      is still shared.
- [ ] Open an issue upstream with the trace and a failing case.
- [ ] Decide, and record here, what this package does when it first connects an
      `HTTPClientTransport` to a real server: wait for the fix, pin a patched
      version, or strip `Last-Event-ID` through the `requestModifier` the sdk
      already offers.

#eventplan