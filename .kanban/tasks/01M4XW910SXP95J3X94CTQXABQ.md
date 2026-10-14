---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4xy8fqs89nk33a8mwbzx84c
  text: |-
    T1 result: swift test, 2376 tests pass (1 run). IntegrationTests do not build yet (T2).

    Changes:
    - New fixture SessionOutputLog: reads streamSessionEvents() from before the first mail; ask(_:) = send + awaitAnswer(of:) with the MailID kept; waits on events (no clock): terminal of a MailID, the run mail of a completion token.
    - SubmissionLog reads SessionOutput: fold(outputs:) groups each chain by its origin; AnswerRecord.origin, answers(_:), deliveredMailIds; answer(to:in:); endsAnswer(_:of:) by MailID. New test mixedAnswersFoldByOrigin.
    - BackgroundSettleGraceTests (7 tests) and MultiToolExecutionTests (2 tests): answers and run mail found by MailID; the TestPoll waits on prompt text and MailProbePrompts.awaiting (poll, now removed) are replaced by event waits. The checks of the prompt text stay as content checks.
    - any RoutedSession in MailProbeFixtures, StubRouterFixtures, MCPElicitationTests.

    Findings:
    - A call that settles inside the settle period makes run mail that Router withdraws and ends with cancelled. "No mail came" is now checked as: only the user mail is delivered, and each run mail ends cancelled.
    - The answer of a settled run can also deliver other run mail of the same run. The check is: the answer delivers only run mail of that run.
  timestamp: 2026-10-14T19:29:36.505019+00:00
depends_on:
- 01M4XW8NPSNVKWPA57P02504T2
position_column: done
position_ordinal: ffffdf80
title: 'Mail step 5 T1: move the test files and ScenarioGrading to Mail, MailID and SessionOutput'
---
Step 5 of the mail work. Read mailbox.md (sections 3, 4 and 5, the signals table, section 8 rows 2 to 5, and the Progress table). All items in mailbox.md are decisions. This task starts after T0.

## Work
- Change the test files (approximately 22) and the ScenarioGrading product to the Router API of step 2 and later.
- SubmissionLog reads SessionOutput.
- Each test must check the same behavior as before.
- Where a test found an answer or a mail by text or by event order, change the test to use the MailID and its terminal.

## Rules
- Write all text (comments, docs, commits, reports, tasks) in STE.
- Commit after the task, with Multitool green. Report to the step 5 owner: the commit, the test result, and each difference from the plan with its reason. Do not push until the owner accepts step 5.
- Run the full suite one time. Do not run tests again and again to find a failure. A test that fails only sometimes is a bad test: find the cause and make it deterministic, or fix the race in the code. Do not use .timeLimit, sleep, clock wait, poll or retry. If a test hangs, take `sample <pid>` of your own test process before you stop it. Stop only your own process ids.
- Ask the owner before a decision that is not in the plan. Do not delete a test without the decision of the owner.

#mail-step-5