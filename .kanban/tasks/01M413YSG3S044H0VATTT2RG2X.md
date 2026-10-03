---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m417nazt5xma3030d7y7xfaq
  text: 'Research: `rg makeWithHeldWatchdog Tests` finds call sites in the 9 files on the card and also in `RunCodeToolTimeoutTests.swift` (the `^e2xvhtk` tests). The `^e2xvhtk` doc comments say "watchdog is held"; they change to "the sandbox has no clock". `JSCInterpreter` still has a `WatchdogState`, but it only polls for cancellation and has no clock, thus the word "watchdog" alone stays correct; only "held watchdog" text is false. `GatedClock` has many other users (ShellRunnerTests, ResilienceTests, MCPTestSupport and others), thus it stays. `HardeningTests.makeHeldMultiTool` keeps its name (no logic change); its doc comment changes. RED check: the acceptance `rg` finds 80+ lines before the change.'
  timestamp: 2026-10-03T15:55:56.282258+00:00
- actor: claude-code
  id: 01m41849xm08e99z9arata4feb
  text: 'Implementation landed. All `JSCInterpreter.makeWithHeldWatchdog()` call sites now use `JSCInterpreter()`: 51 in JSCInterpreterTests, 2 each in CoreLogRecordTests and SearchToolsToolTests, 1 each in TypedMockDryRunTests, MCPCapabilityTests, MetricsTests, SampleSnippetTests, ResultRendererTests, HardeningTests and RunCodeToolTimeoutTests (`^e2xvhtk`). The helper file `Support/JSCInterpreter+HeldWatchdog.swift` is deleted (`git rm`). Doc comments that said "watchdog is held" now say "the sandbox has no clock" (JSCInterpreterTests two places, TypedMockDryRunTests, HardeningTests, RunCodeToolTimeoutTests). `HardeningTests.makeHeldMultiTool` is renamed `makeMultiTool`: "Held" meant the held watchdog, thus the name was false. It is private, with 3 call sites in the same file. `GatedClock` stays: 11 test files construct it. Note for the next agent: the `files` tool `edit file` op does not honor `replace_all`; it replaces only the first match per call.'
  timestamp: 2026-10-03T16:04:06.708675+00:00
- actor: claude-code
  id: 01m4184frt9fnywy0q87va9jwj
  text: |-
    ### implement — changed
    - evidence: 11 test files (10 modified, 1 deleted: `Support/JSCInterpreter+HeldWatchdog.swift`). `rg -i "makeWithHeldWatchdog|heldWatchdog|held watchdog" Tests` finds nothing. `swift build --build-tests` passes. `swift test --filter` over the 10 touched suites: 10 suites pass. `swift test`: 1890 tests in 157 suites pass, 0 failures. No `@Test` line changed, thus the count is the same. The only warning is `missing creator for mutated node` for the mlx-swift_Cmlx bundle, which comes from the build system of a dependency and not from changed code.
    - next: /review
  timestamp: 2026-10-03T16:04:12.698378+00:00
depends_on:
- 01M413X82NWGVNF2XKW8V2FV2Z
position_column: doing
position_ordinal: '80'
title: Remove the makeWithHeldWatchdog test helper
---
## What
After `^8v2fv2z`, `JSCInterpreter.makeWithHeldWatchdog()` returns a plain `JSCInterpreter()`. The sandbox has no clock to hold, so the name is false. Remove the helper and use `JSCInterpreter()` at each call site. This is a mechanical rename. It touches many test files, but it is one concern with no logic change.

- [x] Delete `Tests/FoundationModelsMultitoolTests/Support/JSCInterpreter+HeldWatchdog.swift` (and `heldWatchdogTimeLimit`).
- [x] Replace `JSCInterpreter.makeWithHeldWatchdog()` with `JSCInterpreter()` in: `JSCInterpreterTests.swift`, `TypedMockDryRunTests.swift`, `MCPCapabilityTests.swift`, `MetricsTests.swift`, `SearchToolsToolTests.swift`, `SampleSnippetTests.swift`, `ResultRendererTests.swift`, `CoreLogRecordTests.swift`, `HardeningTests.swift` (all under `Tests/FoundationModelsMultitoolTests/`). Find each site with `rg makeWithHeldWatchdog Tests`.
- [x] Remove doc comments that talk about a "held watchdog" (for example near `JSCInterpreterTests.swift:252`).
- [x] If the `^e2xvhtk` tests used the helper to stop the sandbox clock, change them to `JSCInterpreter()`. They must still pass, because only the engine clock exists now.

## Acceptance Criteria
- [x] `rg -i "makeWithHeldWatchdog|heldWatchdog|held watchdog" Tests` finds nothing.
- [x] `GatedClock` is still used by other tests, or is removed if it has no other user.

## Tests
- [x] `swift test` passes with the same test count, less the tests removed in `^8v2fv2z`.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #cleanup #timeouts