---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m53xaxknzzaedm6t3yfbp4fm
  text: |-
    Implementation (rule R4). The elicitation handler of each attempt client now carries the connect generation of that attempt: makeAttemptClient(over:transportID:generation:) gives it to setupHandlers(on:generation:), which gives it to registerElicitationHandler(on:generation:), which calls answerElicitation(parameters:generation:). answerElicitation compares that generation with connectGeneration, after the headless check and before the schema decode. When they are not equal, the answer is cancel at once through wireResult(of:), with the new reason oldConnectionQuestionReason ("the connection to the MCP server ended before the question") under _meta.reason, and a debug record mcpElicitationCancelledOldConnection. No context and no host handler is asked. Thus the question cannot attach to the run or to the handler of the new generation. resolve(...) and openContextElicitation(...) also take the generation, and pendingContextElicitations records the generation of the attempt, not connectGeneration.

    Why not connectionEndedReason: its text names a URL flow that was accepted ("before the URL flow completed"). The new guard also stops a form question, and no flow started. Thus a new reason.

    Tests (MCPElicitationTests), fixed order with no new production hook: (1) aQuestionOfAnOldClientDoesNotReachTheRun: the server connects two times (an empty scripted server, then the scripted server of the held tool), a held call under a context is in flight on the second connection (wait ends on arrival or on the end of the call), then answerElicitation is called with the generation of the first connect. The sink declines at once, thus a question that reaches the run ends with no test step. (2) aQuestionOfAnOldClientDoesNotReachTheHandler, over disconnect and new connect: a handler that declines at once, the connection ends, then the question comes with the old generation. The direct call of answerElicitation with the old generation is the same call that the handler closure of the old client makes, thus no hook in production code was necessary.

    RED: after the signature plumbing only, both tests failed (9 issues: the run and the handler got the question, the answer was decline with no reason). GREEN: both pass after the guard.

    Discovery, not in the scope of this card: a host handler that was called before the generation moved and answers accept after endHeldHostElicitations() ran is held in pendingHostElicitations of the new generation. I added a separate card for it.
  timestamp: 2026-10-17T03:08:54.261268+00:00
- actor: claude-code
  id: 01m53xbe66wtftr6dg4aevxpya
  text: |-
    ### implement — changed
    - evidence: 5 files — Sources/FoundationModelsMultitool/Capabilities/MCP/MCPServer+Elicitation.swift, MCPServer+Connection.swift, MCPServer+ClientLifecycle.swift, MCPServer.swift (doc reference), Sources/FoundationModelsMultitool/Diagnostics/MultitoolTelemetry.swift; Tests/FoundationModelsMultitoolTests/MCPElicitationTests.swift. RED: swift test --filter aQuestionOfAnOldClient, 2 tests failed with 9 issues. GREEN: same filter, 2 tests passed. Full run: swift test, exit 0, "Test run with 2440 tests in 211 suites passed".
    - next: /review. Follow-up card ^mdr1wq4 for the late host-handler accept.
  timestamp: 2026-10-17T03:09:11.238359+00:00
- actor: claude-code
  id: 01m53xddh41rrknq44wxngjqmj
  text: |-
    ### test - green
    - evidence: `swift test` ran one time. Exit code 0. Summary line: "Test run with 2440 tests in 211 suites passed after 3.724 seconds."
    - 0 failures. No test skipped by the runner. No test was changed. No fix was needed.
    - The build log has one SwiftPM line: "warning: missing creator for mutated node" for the mlx-swift_Cmlx.bundle. It comes from the build system and not from the project source.
    - next: review.
  timestamp: 2026-10-17T03:10:16.100706+00:00
- actor: claude-code
  id: 01m53xe53ph1cgty1vb20712gq
  text: |-
    ### commit — changed
    - evidence: subject "fix(mcp): record the connect generation of the attempt that got a context URL question"; the sha is in the step block returned to the caller (a comment cannot hold the sha of the commit that contains it)
    - next: review
  timestamp: 2026-10-17T03:10:40.246942+00:00
position_column: doing
position_ordinal: '8280'
title: Record the connect generation of the attempt that got a context URL question
---
Found during ^aj384vm.

`openContextElicitation(_:request:context:)` in MCPServer+Elicitation.swift records `connectGeneration`, the current generation of the actor. It does not record the generation of the attempt whose client got the `elicitation/create`. A new connect and `disconnect()` move the generation before they retire the old client. An old client can deliver a request after the move (for example during `waitUntilTransportClosed` in `retireCurrentClient()`). That request then gets the new generation. The relay of its wire completion uses the old generation, thus `complete(elicitationId:generation:)` drops the completion. `endOldContextElicitations()` also skips the entry, because its generation is not older. The question can then stay open.

Work:
- Give the generation of the attempt to the elicitation handler (`registerElicitationHandler(on:)` gets it from `makeAttemptClient(over:transportID:generation:)`), and record that generation in `pendingContextElicitations`.
- Start with a fixed-order RED test (rule T1), then the fix. #elicitation-fixes