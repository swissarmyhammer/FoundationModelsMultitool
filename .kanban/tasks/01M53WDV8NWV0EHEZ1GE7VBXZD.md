---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m53xxsanz6n4fvj20cjwf44h
  text: |-
    ### priority — owner (2026-10-17)
    - This card comes before T1 (^nvxckvr), and before ^mdr1wq4. It leaves a question that nothing ends (the same class as group A).
    - The answer: the second question must end at once with cancel and a reason in `_meta.reason`, or get an entry that a disconnect ends. Start with a test that fails on the current code.
    - Push: this card and ^mdr1wq4 go together in one push, after the push of ^179vr1r, ^fcvjb8j and ^7y77mjf.
  timestamp: 2026-10-17T03:19:12.469543+00:00
- actor: claude-code
  id: 01m53yq16zxs4eh08exgatsr1g
  text: |-
    ### research
    - `openContextElicitation(_:request:context:generation:)` returns `false` when the wire id is in use, and `resolve` then calls `elicit(_:through:)` for the newer question with no entry. The defer of `resolve` removes an entry only when the entry id is the id of its own question. Thus when the newer question replaces the entry, the defer of the earlier question does not remove the entry of the newer question.
    - `ToolContext.endElicitation(_:with:)` ends an accepted URL question on its run plane (the same call as `endOldContextElicitations()`).
    - Plan: the newer question gets the entry; the earlier question ends at once with cancel and `replacedByNewerFlowReason` through `endElicitation`. No test hook is necessary.
    - Test plan: one held call under a context over a test-owned RunPlane (`whileHolding`), then two direct `answerElicitation` calls with the one wire id. The test reads the wire result of each question, the entry after the second question, and the wire completion of the id.
  timestamp: 2026-10-17T03:32:59.743689+00:00
- actor: claude-code
  id: 01m53yy5fvm8bt6sm2cpy8mwbf
  text: |-
    ### implementation
    - Answer used: the newer question wins. `openContextElicitation` is now `async`: it puts the entry of the newer question in `pendingContextElicitations` (`updateValue`), writes the `mcpElicitationWireIdInUse` record, and ends the earlier question with cancel and `replacedByNewerFlowReason` through `ToolContext.endElicitation(_:with:)`. No test hook was necessary.
    - The defer of `resolve` removes the entry only when its id is the id of its own question, thus the defer of the earlier question keeps the entry of the newer question. The test shows this: the map is empty only after the newer question ends.
    - Docs updated: the header of MCPServer+Elicitation.swift, `replacedByNewerFlowReason`, `openContextElicitation`, and the doc of `LogMessage.mcpElicitationWireIdInUse` in MultitoolTelemetry.swift (the log text did not change).
    - New test `aSecondContextQuestionUnderAWireIdInUseReplacesTheEarlierQuestion` and helper `startContextURLQuestion(on:sink:after:)` in MCPElicitationTests.swift. RED on the old code: 5 issues (the entry id, the ended list, the late completion of the newer question, the action and the reason of the earlier answer). GREEN after the fix.
    - Process note: I ran the RED filter a second time with `--skip-build` and no code change, only to read the issue lines that my first output filter dropped.
  timestamp: 2026-10-17T03:36:53.499351+00:00
- actor: claude-code
  id: 01m53yy8g41mz3gaet6q9knw5s
  text: |-
    ### implement — changed
    - evidence: 3 source files — Sources/FoundationModelsMultitool/Capabilities/MCP/MCPServer+Elicitation.swift, Sources/FoundationModelsMultitool/Diagnostics/MultitoolTelemetry.swift, Tests/FoundationModelsMultitoolTests/MCPElicitationTests.swift. RED: 5 issues on the old code. GREEN: the new test passed. Full run `swift test`: "Test run with 2444 tests in 211 suites passed", XCTest "Executed 0 tests, with 0 failures". One build-system warning only, from the mlx-swift dependency bundle ("missing creator for mutated node"), not from this change. The exit code of swift test was not captured because the output went through a pipe.
    - next: review
  timestamp: 2026-10-17T03:36:56.580160+00:00
- actor: claude-code
  id: 01m53z03dv76gt0frm4rwzzs73
  text: |-
    ### test - green
    - command: swift test (one run, exit code kept from swift test itself)
    - exit code: 0
    - Swift Testing summary: Test run with 2444 tests in 211 suites passed after 4.874 seconds.
    - XCTest: Executed 0 tests, with 0 failures.
    - No test failed. No test skipped. No source warning.
    - Build note: SwiftPM printed one build-system line: "warning: missing creator for mutated node" for the mlx-swift_Cmlx.bundle. It is not from project source.
    - next: review
  timestamp: 2026-10-17T03:37:56.923720+00:00
position_column: doing
position_ordinal: '8280'
title: A second context URL question under a wire id in use has no entry, thus no wire completion and no connection end can end it
---
Found during ^179vr1r.

In MCPServer+Elicitation.swift, `openContextElicitation(_:request:context:)` does not add an entry when an open question of a context already uses the wire id. It writes `mcpElicitationWireIdInUse` and returns `false`. Then `resolve(_:urlElicitationId:linkedBy:)` calls `elicit(_:through:)` for the newer question with no entry in `pendingContextElicitations`.

Results:
- A wire completion of that id goes only to the earlier question.
- `endOldContextElicitations()` reads only the map, thus a disconnect or a new connect does not end the newer question.
- After the earlier question ends, its `defer` removes the entry, and the newer question still has no entry.

Thus the newer URL question can wait until the host session ends it. Decide the correct answer for the newer question (for example a cancel with a reason in `_meta`, at once, as the held flow of the handler does now with `replacedByNewerFlowReason`), and if the earlier question must end.

Start with a fixed-order test that fails on the current code: two URL questions of one bound context under one wire id; the test reads the result of each question on the wire. No time limit, sleep, poll or retry. #elicitation-fixes