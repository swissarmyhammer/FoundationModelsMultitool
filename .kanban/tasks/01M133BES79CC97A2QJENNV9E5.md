---
assignees:
- claude-code
position_column: todo
position_ordinal: '9280'
title: The HTTP-loopback elicitation tests time out on about one full swift test run in six
---
## What

`swift test` at the root fails intermittently. Two tests carry the failure,
and both drive an elicitation over the in-process HTTP loopback:

- `LoopbackHTTPServerTests.elicitEchoRoundTrip` — "a server-initiated
  elicitation/create reaches the client, and the answer returns to the tool",
  at `Tests/FoundationModelsMultitoolTests/LoopbackHTTPServerTests.swift:110`.
- `MCPElicitationTests` — "a runCode snippet suspends on the elicitation and
  returns the mailbox answer over the HTTP loopback", at
  `Tests/FoundationModelsMultitoolTests/MCPElicitationTests.swift:295`, which
  reports through `Support/PollFixtures.swift:77`.

The first fails with a `URLSession` request timeout, not an assertion:

```
Caught error: Error Domain=NSURLErrorDomain Code=-1001 "The request timed out."
NSErrorFailingURLStringKey=http://loopback-<uuid>/mcp
```

The test then reports after 120 seconds, and the whole run reports after 121
seconds. A clean run of the same suite takes about 6 seconds, so a red run
takes 20 times the time of a green one.

## The measurement

Made on 2026-08-27, with `swift test` at the root, on an Apple silicon
machine:

| the tree | runs | red |
|---|---|---|
| `HEAD` = `1d2708b`, no working change | 8 | 1 |
| the same, plus the `^bgvekc2` change | 17 | 3 |

The `^bgvekc2` change touches `.github/workflows/ci.yml`, `README.md` and
`CIWorkflowTests.swift` alone, and it adds one test that reads a file. The
baseline column is what states the cause: the failure is already there with
no working change, so no change of that task causes it. About one run in six
is red.

## Why the present mitigation is not enough

`LoopbackHTTPServerTests` carries `.serialized` for this cause, and its doc
comment states the earlier measurement: each test holds a live SSE stream
open through `URLSession` for its whole body, the SSE read of the client runs
on the shared cooperative thread pool, and several such streams at once stall
a server-to-client message.

`.serialized` makes the tests of THAT suite run one at a time. It does not
stop the rest of the parallel `swift test` run — `MCPElicitationTests`
included, which opens a loopback stream of its own — from loading the same
pool. Thus the stall stays.

## Acceptance Criteria

- [ ] Find why the server-to-client message stalls when the cooperative pool
      is loaded. State whether the stall is in `LoopbackHTTPServer`, in the
      SSE read of `HTTPClientTransport`, or in the pool itself.
- [ ] Remove the cause. Give the SSE read a thread that a loaded pool cannot
      hold, or remove the blocking wait. Do not raise a timeout, and do not
      make the tests of the two suites serial with each other: each is a
      report of the cause, not a removal of it.
- [ ] Keep both tests in the unit target. Add no environment variable and no
      skip.

## Tests

- [ ] 30 consecutive full `swift test` runs, each green.

## Workflow
Read the doc comment of `LoopbackHTTPServerTests` first. It carries the
earlier measurement and the reason for `.serialized`. #eventplan