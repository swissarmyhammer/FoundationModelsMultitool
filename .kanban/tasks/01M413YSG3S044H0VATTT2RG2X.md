---
assignees:
- claude-code
depends_on:
- 01M413X82NWGVNF2XKW8V2FV2Z
position_column: todo
position_ordinal: '8380'
title: Remove the makeWithHeldWatchdog test helper
---
## What
After `^8v2fv2z`, `JSCInterpreter.makeWithHeldWatchdog()` returns a plain `JSCInterpreter()`. The sandbox has no clock to hold, so the name is false. Remove the helper and use `JSCInterpreter()` at each call site. This is a mechanical rename. It touches many test files, but it is one concern with no logic change.

- [ ] Delete `Tests/FoundationModelsMultitoolTests/Support/JSCInterpreter+HeldWatchdog.swift` (and `heldWatchdogTimeLimit`).
- [ ] Replace `JSCInterpreter.makeWithHeldWatchdog()` with `JSCInterpreter()` in: `JSCInterpreterTests.swift`, `TypedMockDryRunTests.swift`, `MCPCapabilityTests.swift`, `MetricsTests.swift`, `SearchToolsToolTests.swift`, `SampleSnippetTests.swift`, `ResultRendererTests.swift`, `CoreLogRecordTests.swift`, `HardeningTests.swift` (all under `Tests/FoundationModelsMultitoolTests/`). Find each site with `rg makeWithHeldWatchdog Tests`.
- [ ] Remove doc comments that talk about a "held watchdog" (for example near `JSCInterpreterTests.swift:252`).
- [ ] If the `^e2xvhtk` tests used the helper to stop the sandbox clock, change them to `JSCInterpreter()`. They must still pass, because only the engine clock exists now.

## Acceptance Criteria
- [ ] `rg -i "makeWithHeldWatchdog|heldWatchdog|held watchdog" Tests` finds nothing.
- [ ] `GatedClock` is still used by other tests, or is removed if it has no other user.

## Tests
- [ ] `swift test` passes with the same test count, less the tests removed in `^8v2fv2z`.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #timeouts #cleanup