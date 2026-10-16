---
assignees:
- claude-code
position_column: done
position_ordinal: fffff980
title: waitUntilZombie in StdioServerProcessTests waits with waitid on a cooperative pool thread
---
StdioServerProcessTests.swift:216 (old) called waitid(P_PID, WEXITED|WNOWAIT) with no WNOHANG from async test code. The call stops a cooperative pool thread until the child exits.

Fix: waitUntilZombie is now async. It runs waitid on a dedicated thread through the new DedicatedThread.run (Sources/FoundationModelsMultitool/Capabilities/MCP/DedicatedThread.swift) and resumes a continuation.

Test: DedicatedThreadTests.theBodyRunsWithNoCurrentTask. On the old shape (body runs inline on the pool) the test fails as a check: `Expectation failed: !ranInATask`. On the new code it passes.

Part of the freeze card ^3ytqp5q. #bad-test