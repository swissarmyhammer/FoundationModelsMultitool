---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3fmz005qg8bqzj80zjm4t8b
  text: 'Task ^hd44hre covers this card (its third item). Commit 1003470 "feat(cli): take the reply from the answered event, report answerFailed, and print mail answers" adds `CLIRunner.drainMailAnswers(_:after:wait:cancel:output:)` in Sources/MultitoolCLI/CLIAnswerDrain.swift. The CLI subscribes to `streamSessionEvents()` before it sends the prompt. After the first answer, it prints each answer that mail starts ("Answer from mail: ...") until the session is idle for a quiet period (no open submission, no caller message with no answer, no open background run). The bound is `CLIMailWait.demo` (time limit `MultiToolConfiguration.defaultExecutionTimeLimit`), then the CLI calls `cancel()`. Test: CLIAnswerDrainTests.mailAnswerIsPrintedBeforeExit. Follow-up commit 5ca8edf is the review fix of ^hd44hre.'
  timestamp: 2026-09-26T20:02:04.421918+00:00
position_column: todo
position_ordinal: 8b80
title: 'CLI demo: print the answer that mail starts after a background run settles'
---
## What
After the removal of the `wait` tool (task ^q4jrnd0), a settled background run comes back to the session as mail. The mail starts a new answer, and that answer streams on `RoutedSession.streamSessionEvents()`, not on `streamEvents(to:)`. `CLIRunner` (`Sources/MultitoolCLI/CLIRunner.swift`, the `drainTurn` call near the `demoPrompt`) drains `streamEvents(to:)` only, so the demo prints the first answer ("the result comes back later") and not the answer from the mail.

- [ ] After the first answer, drain `streamSessionEvents()` until the answer that mail starts ends (`SessionEvent.answered`), or until no background run is left. Print that answer as the demo answer.
- [ ] Keep the drain bounded: use a named time limit constant.

## Acceptance Criteria
- [ ] The demo prints the answer that the mail started when a `runCode` snippet outlasts the inline settle grace.

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/CLITurnDrainTests.swift`: a scripted event stream with an `answered` event from mail gives that answer.
- [ ] Run `swift test`. Expected result: all tests pass.