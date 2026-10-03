---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: LostCallTests no-auto-retry case waits 300 ms to learn that no retry came
---
## What
`LostCallTests.noAutoRetryAfterReconnectEvenForIdempotentHintedTool` reconnects the server, then sleeps for `autoRetryGraceWindow` (300 ms), and then asserts that the handler of the hanging tool ran one time only. The sleep is a deadline that the test waits for to learn that an event (a re-sent call) did not come. The rule of ^fafvwrc is: no test waits for a deadline to learn that an event did not come.

Found during ^fafvwrc. That card changed only the `guard` of this test to an `#expect`. It did not change the sleep, because the card is about the four tests that read an inner terminal.

Subtasks:
- [ ] Find a synchronization point that proves that no call is re-sent after the reconnect, with no sleep. One possible point: after the reconnect, make one more call on the same connection and read the order of the requests that the new scripted server recorded. If no such point is possible without a clock, record why on this card and ask the user.

## Acceptance Criteria
- [ ] The no-auto-retry test has no sleep and no deadline that it waits for to learn that a retry did not come.
- [ ] The test still fails when a change re-sends a `lost` call after the reconnect.

## Tests
- [ ] `swift test --filter LostCallTests` passes. `swift test` passes. #defect #timeouts