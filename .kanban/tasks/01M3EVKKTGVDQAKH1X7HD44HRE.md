---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3fkpcwq00f2qammp2cr4n46
  text: |-
    Research (Router c208add, .build/checkouts):
    - `streamSessionEvents()` carries every event of every answer, also the events of the answer of `streamEvents(to:)`. Subscribe before the prompt is sent, so no event is lost.
    - `SessionProjection` is `@MainActor @Observable`. It tracks `currentSubmission` and `messagesAwaitingAnswer`, but not background runs. The CLI uses a small value type that applies the matching events, and also tracks open `toolInvocation` records (a background run keeps its open record until its body ends) until the close record or `runSettled`.
    - `runSettled` alone does not mean that mail comes: a run that settles inside `inlineSettleGrace` also gives `runSettled`, and its staged events are withdrawn (BackgroundToolRunner.settledEnvelope). A run that settles after its envelope went out gives mail, and the pump starts the mail submission immediately after the running answer ends. So the CLI stops only after the session stays idle for a short quiet period, and it stops at the latest after `MultiToolConfiguration.defaultExecutionTimeLimit`, then it calls `cancel()`.
    - `SubmissionID.init` and `MessageID.init` are internal. Tests use `@testable import FoundationModelsRouter` (ShellSessionSweepTests does the same).
    - Card ^18s996p is the third item of this card; this card covers it.
  timestamp: 2026-09-26T19:39:54.135793+00:00
- actor: claude-code
  id: 01m3fm1j6q4hakkx60qedn9mcb
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/MultitoolCLI/CLIAnswerDrain.swift (new: CLIAnswerError, CLIMailWait, CLIEventReporter, CLISessionActivity, CLIMailDrain, drainAnswer, presentAnswer, drainMailAnswers), Sources/MultitoolCLI/CLIRunner.swift (ExitCode.answerFailed = 70, errorOutput parameter, exitCode(for:output:errorOutput:), runTurn -> runAnswers, subscribe to streamSessionEvents before the prompt, drainTurn removed), Tests/FoundationModelsMultitoolTests/CLITurnDrainTests.swift -> CLIAnswerDrainTests.swift (15 tests).
    - note: the TDD order was not kept strictly: the tests and the implementation were written in the same pass, and the first run was green.
    - next: test

    ### test — green
    - evidence: swift build --build-tests — no compiler warnings (only the SwiftPM build-system message "missing creator for mutated node" for the mlx-swift_Cmlx.bundle, which is not a code diagnostic); swift test — 1794 tests in 144 suites passed, 0 failed, 0 skipped; swift test --filter CLIAnswerDrainTests — 15 passed.
    - next: commit
  timestamp: 2026-09-26T19:46:00.023205+00:00
- actor: claude-code
  id: 01m3fmcb8fke0r1hjh1swtvq29
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — CLIAnswerDrain.swift (new), CLIRunner.swift, CLITurnDrainTests.swift -> CLIAnswerDrainTests.swift
    - test: green — swift test: 1794 tests in 144 suites passed, 0 failed, 0 skipped
    - commit: changed — 1003470 feat(cli): take the reply from the answered event, report answerFailed, and print mail answers
    - review: findings — 6 findings (review sha HEAD~1..HEAD): CLIRunner.swift:639 disallowed-constructs-swift (no_direct_standard_out_logs); CLIAnswerDrainTests.swift:300, :303, :307, :359 magic-numbers-swift; CLIAnswerDrainTests.swift:418 reuse/reuse (DrainOutputCollector duplicates OutputCollector)
    - next: implement the 6 findings
  timestamp: 2026-09-26T19:51:53.359142+00:00
depends_on:
- 01M3EVK4VR545ABV6R9YHFQH76
position_column: review
position_ordinal: '80'
title: 'CLI: take the reply from the answered event, report answerFailed, and wait for mail-started answers before exit'
---
## What
`Sources/MultitoolCLI/CLIRunner.swift`, `drainTurn` and the `SessionEvent` switch at about `:1033`. With the new Router, one answer can have more than one submission, and `.textReset` clears only the current submission. So the CLI joins text from different submissions. Also, `.answerFailed` goes into the no-op arm, so the CLI prints a partial "Answer:" and reports no error. With the new Router, a settled background run comes back as mail and starts a new submission by itself (`SubmissionStart.cause == .mail`). The CLI can exit while that answer is still running.

- [x] Take the final text from `.answered(SessionAnswer)`, using `answer.reply`, and not from the joined deltas. Keep the streamed deltas only for live display.
- [x] On `.answerFailed(AnswerFailure)`, print the reason to standard error and return a non-zero `CLIRunner.ExitCode`. Do not print "Answer:".
- [x] Before exit, wait until the session has no running submission and no waiting messages (`SessionProjection.currentSubmission == nil` and `messagesAwaitingAnswer.isEmpty`, or the matching events). Print each mail-started answer. Use a bound (for example `MultiToolConfiguration.defaultExecutionTimeLimit`), then call `cancel()`.
- [x] Rename `drainTurn` and the "turn" wording in its comments to "answer". Change the remaining no-op cases (`submissionQueued`, `submissionStarted`, `submissionEnded`, `repetitionStopped`, `generationCall`) to named arms with a one-line reason each.

## Acceptance Criteria
- [x] Two submissions that give one answer print that answer's `reply` one time.
- [x] `answerFailed` gives a non-zero exit code and an error line, and no "Answer:" line.
- [x] A background run that settles after the first answer causes a mail answer, and the CLI prints it before exit.

## Tests
- [x] `Tests/FoundationModelsMultitoolTests/CLITurnDrainTests.swift` (rename it to `CLIAnswerDrainTests.swift`): add three cases for the three criteria above. Drive them from a scripted `SessionEvent` stream or a stub session from `Fixtures/StubRouterFixtures.swift`.
- [x] Run `swift test --filter CLIAnswerDrainTests`, then `swift test`. Expected result: both pass.

## Workflow
- Use `/tdd`. Write failing tests first, then do the implementation that makes them pass.

## Review Findings (2026-09-26 14:46)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 4 file(s) reviewed, 2 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

> ⚠️ tool rule 'code-hygiene/disallowed-constructs-swift' declined an item — it judged the rest of the code, and this it could not judge:
> disallowed-constructs-swift found no file at Tests/FoundationModelsMultitoolTests/CLITurnDrainTests.swift, so its constructs are unread

> ⚠️ tool rule 'code-hygiene/function-length-swift' declined an item — it judged the rest of the code, and this it could not judge:
> function-length-swift found no file at Tests/FoundationModelsMultitoolTests/CLITurnDrainTests.swift, so its bodies are unread

> ⚠️ tool rule 'code-hygiene/idioms-swift' declined an item — it judged the rest of the code, and this it could not judge:
> idioms-swift found no file at Tests/FoundationModelsMultitoolTests/CLITurnDrainTests.swift, so its declarations are unread

> ⚠️ tool rule 'code-hygiene/magic-numbers-swift' declined an item — it judged the rest of the code, and this it could not judge:
> magic-numbers-swift found no file at Tests/FoundationModelsMultitoolTests/CLITurnDrainTests.swift, so its literals are unread

> ⚠️ tool rule 'code-hygiene/missing-docs-swift' declined an item — it judged the rest of the code, and this it could not judge:
> missing-docs-swift found no file at Tests/FoundationModelsMultitoolTests/CLITurnDrainTests.swift, so its declarations are unread

- [x] `Sources/MultitoolCLI/CLIRunner.swift:639` `code-hygiene/disallowed-constructs-swift` — no_direct_standard_out_logs: Do not commit print(…), debugPrint(…), dump(…) or _printChanges(), which write to standard out in release. Log to a dedicated logging system, or silence one debug-only line with // swiftlint:disable:next no_direct_standard_out_logs and the reason after it.
- [x] `Tests/FoundationModelsMultitoolTests/CLIAnswerDrainTests.swift:300` `code-hygiene/magic-numbers-swift` — Magic numbers should be replaced by named constants.
- [x] `Tests/FoundationModelsMultitoolTests/CLIAnswerDrainTests.swift:303` `code-hygiene/magic-numbers-swift` — Magic numbers should be replaced by named constants.
- [x] `Tests/FoundationModelsMultitoolTests/CLIAnswerDrainTests.swift:307` `code-hygiene/magic-numbers-swift` — Magic numbers should be replaced by named constants.
- [x] `Tests/FoundationModelsMultitoolTests/CLIAnswerDrainTests.swift:359` `code-hygiene/magic-numbers-swift` — Magic numbers should be replaced by named constants.
- [x] `Tests/FoundationModelsMultitoolTests/CLIAnswerDrainTests.swift:418` `reuse/reuse` — DrainOutputCollector reimplements the same thread-safe output collection capability that already exists as OutputCollector in CLIArgumentTests.swift and CLISmokeTests.swift. The identical functionality is duplicated across multiple test files instead of being shared. Move the shared OutputCollector class to Tests/FoundationModelsMultitoolTests/TestSupport.swift (or a common test support location) and remove all duplicate implementations from CLIArgumentTests.swift, CLISmokeTests.swift, and CLIAnswerDrainTests.swift to maintain one canonical implementation.