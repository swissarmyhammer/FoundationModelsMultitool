---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4y1cme5ng7w1ez2rg8s496m
  text: 'Fixed. `startBareTimeout` now sleeps on an injected clock. The clock is a new internal stored property `callTimeoutClock` (the internal init takes it; the public init gives `ContinuousClock()`). It is not `clock`: the test helpers give `clock` a `ManualClock` whose sleeps end at once, and a bare-call timer on that clock would end every bare call of those tests at once. This follows the pattern of `clientQueueClock` and `connectAttemptClock`. `MCPTestSupport.makeServer` gives a `GatedClock` that no test opens as the default. New test: `MCPServerCallTests.aBareCallTimesOutOnlyOnTheInjectedClock`. It failed on the old code (3 issues) and passes with the fix. MetricsTests and MCPTracePropagationTests now use a `ManualClock` for the bare-call timer, and their hanging tools wait on a gate that no one opens.'
  timestamp: 2026-10-14T20:24:18.117965+00:00
depends_on: []
position_column: done
position_ordinal: ffffe180
title: 'Defect: MCPServer bare-call timeout ignores the injected clock'
---
Found in mail step 5, T3.

Sources/FoundationModelsMultitool/Capabilities/MCP/MCPServer+Call.swift:410: `startBareTimeout` calls `Task.sleep(for: timeout)`. It does not use the `clock` that the server gets at init. Thus a test of the bare-call timeout (MetricsTests, MCPTracePropagationTests, `callTimeout: 100ms`) waits on real time.

Proposed fix (needs the decision of the step 5 owner): sleep on `self.clock`. The tests then give a ManualClock or a GatedClock and do not wait on real time.

#mail-step-5 #defect