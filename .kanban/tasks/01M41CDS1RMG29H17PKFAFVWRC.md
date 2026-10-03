---
assignees:
- claude-code
depends_on:
- 01M4141K70F8V1TV6BK1CH4DHB
position_column: todo
position_ordinal: 8c80
title: Update four tests that read an inner terminal through the mount sink, after the Extras fix e7e09a6
---
## What
FoundationModelsExtras commit e7e09a6 (local, not pushed yet; task ^1ch4dhb) changes `MountedRunUpstreamSink`. A synchronous call that `ToolContext.mount(_:op:as:)` mounted now sends its terminal event to the mounting run as a `.progress` event with the same detail. Before, it went up as a `.completed` event of the mounting run.

Four tests in this package read the inner terminal through the mount sink of the captured stub-run context (`makeStubRun().context`). With the local Extras (`swift package edit`), they fail:
- `MCPServerCallTests` "a mounted call posts its progress events then exactly one completed, in that order" — `kinds.last == .completed` and `events.last?.outcome == .succeeded` fail.
- `LostCallTests` "a transport dropped before the call throws lost, and the run posts exactly one completed event with outcome lost" — no `runSettled` event comes; the test waits about 320 seconds, then `completed.count` and `.lost` fail.
- `RunBindingTests` "two parallel inner calls under Promise.all carry distinct completion tokens and post to the same session" — the progress details now also hold the details of the two inner terminals.
- `HostAndEmitterTests` "runCode casts to ForkableTool off an any Tool existential, and the erased forked() return downcasts and serves the registry" — the same cause.

These tests pin the old route, which is the defect of ^1ch4dhb: an inner terminal took the place of the terminal of the mounting run.

Subtasks:
- [ ] After the user pushes FoundationModelsExtras and runs `swift package update` here, read the inner terminal in MCPServerCallTests and LostCallTests from a sink of the inner run itself (`mount(_:op:as:postingTo:)`, as `concurrentCallsAreDistinguishableByCorrelationID` does), so that each test keeps its intent: the inner run gives its progress events and then exactly one terminal event.
- [ ] In RunBindingTests and HostAndEmitterTests, expect the progress details of the inner tools and the details of the inner terminals, or filter to the details that the tools posted.

## Acceptance Criteria
- [ ] The four tests pass against FoundationModelsExtras with e7e09a6.
- [ ] No test waits for a deadline to learn that an event did not come.

## Tests
- [ ] `swift test --filter 'MCPServerCallTests|LostCallTests|RunBindingTests|HostAndEmitterTests|InnerTerminalEventTests'` passes. `swift test` passes. #timeouts #extras #defect