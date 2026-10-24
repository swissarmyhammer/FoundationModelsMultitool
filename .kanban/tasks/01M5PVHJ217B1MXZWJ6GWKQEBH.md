---
assignees:
- claude-code
position_column: done
position_ordinal: ffffffdd80
title: Drop test uses of GenerationQueueError.waitInsideOpenSubmission (after Router sha)
---
BLOCKED until foundationmodelsacpagent-83 sends the Router sha that removes the same-model refusal. The user decided on 2026-10-24 that the only lock is MLX's FIFO lock, and it is held over the model call only: "locks must not cross over a tool call -- ONLY -- over the actual call into the model". After that change, Extras deletes `GenerationQueueError.waitInsideOpenSubmission`.

Uses to remove or restate:
- Tests/FoundationModelsMultitoolTests/SearchToolsToolTests.swift:366 (`sameModelRefusal`)
- Tests/FoundationModelsMultitoolTests/SampleSnippetTests.swift:224
- Tests/Support/ScenarioGrading/ScenarioGrading.swift:81, 451-546 (refusal outcome and grading)
- Tests/FoundationModelsMultitoolTests/ScenarioGradingTests.swift:238
- the doc comment at Sources/FoundationModelsMultitool/Discovery/SearchToolsTool+Seams.swift:36

Test first: if a test proves the refusal, restate it so the nested same-model call completes. Run the full `swift test`, then commit and push, and send the sha to the peer. #blocked