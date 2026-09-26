---
assignees:
- claude-code
depends_on:
- 01M3EVK4VR545ABV6R9YHFQH76
position_column: todo
position_ordinal: '8880'
title: 'CLI: take the reply from the answered event, report answerFailed, and wait for mail-started answers before exit'
---
## What
`Sources/MultitoolCLI/CLIRunner.swift`, `drainTurn` and the `SessionEvent` switch at about `:1033`. With the new Router, one answer can have more than one submission, and `.textReset` clears only the current submission. So the CLI joins text from different submissions. Also, `.answerFailed` goes into the no-op arm, so the CLI prints a partial "Answer:" and reports no error. With the new Router, a settled background run comes back as mail and starts a new submission by itself (`SubmissionStart.cause == .mail`). The CLI can exit while that answer is still running.

- [ ] Take the final text from `.answered(SessionAnswer)`, using `answer.reply`, and not from the joined deltas. Keep the streamed deltas only for live display.
- [ ] On `.answerFailed(AnswerFailure)`, print the reason to standard error and return a non-zero `CLIRunner.ExitCode`. Do not print "Answer:".
- [ ] Before exit, wait until the session has no running submission and no waiting messages (`SessionProjection.currentSubmission == nil` and `messagesAwaitingAnswer.isEmpty`, or the matching events). Print each mail-started answer. Use a bound (for example `MultiToolConfiguration.defaultExecutionTimeLimit`), then call `cancel()`.
- [ ] Rename `drainTurn` and the "turn" wording in its comments to "answer". Change the remaining no-op cases (`submissionQueued`, `submissionStarted`, `submissionEnded`, `repetitionStopped`, `generationCall`) to named arms with a one-line reason each.

## Acceptance Criteria
- [ ] Two submissions that give one answer print that answer's `reply` one time.
- [ ] `answerFailed` gives a non-zero exit code and an error line, and no "Answer:" line.
- [ ] A background run that settles after the first answer causes a mail answer, and the CLI prints it before exit.

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/CLITurnDrainTests.swift` (rename it to `CLIAnswerDrainTests.swift`): add three cases for the three criteria above. Drive them from a scripted `SessionEvent` stream or a stub session from `Fixtures/StubRouterFixtures.swift`.
- [ ] Run `swift test --filter CLIAnswerDrainTests`, then `swift test`. Expected result: both pass.

## Workflow
- Use `/tdd`. Write failing tests first, then do the implementation that makes them pass.