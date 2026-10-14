---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4xxfh797h4t5b15mam6xaz8
  text: |-
    T0 report (no code change).

    Pins (Package.resolved is gitignored in both packages): Router 2edb4a11, Extras b68a5d4, MetadataRegistry 858f5da3, CodeContext d4c4482a, Ranker 61563468. Multitool does not depend on Agents or ACPAgent. Local pin fix: swift-distributed-tracing had to go from 1.5.0 to 1.7.1, because Sources uses InstrumentationContext (commit 9c9567f). No code change.

    Root package:
    - Sources: builds.
    - ScenarioGrading product: builds. SubmissionLog.fold(events:) still reads [SessionEvent] and finds each answer chain by event order. T1 changes it to SessionOutput, grouped by origin.
    - Tests: one file breaks, ScenarioGradingTests.swift, 24 errors: messageIds -> mailIds and MessageID -> MailID in SubmissionStart, SessionAnswer and AnswerFailure. Build with -continue-building-after-errors confirms that no other test file breaks: the other files use respond(to:), streamEvents(to:) and streamResponse(to:), which stay as helpers.
    - Warnings: MailProbeFixtures.swift:264 and :321 (RoutedSession -> any RoutedSession).

    IntegrationTests:
    - ScenarioRunner.swift:419: exhaustive switch in streamTurn has no case for mailDelivered, cancelled, signalDone, lost.
    - ScenarioRunner.swift:852: streamSessionEvents() gives AsyncStream<SessionOutput>; eventsThroughMailAnswer takes AsyncStream<SessionEvent>.
    - Warning ScenarioRunner.swift:414 (any RoutedSession). StubRouterProfile builds.

    Gap G1 (public API, Router): Router.useRunClock(_:) is internal, and LanguageModelProfile.init(runClock:) is package. Multitool tests get their ToolContext from a stub Router session (StubRouterFixtures), so they cannot give a ManualRunClock to the run plane. Tests affected: the inline settle grace waits (InlineSettleGraceTests besideSlowToolGrace, MultiToolExecutionTests collectorGrace) and other context.wait(completionToken:seconds:) waits. Proposal: make Router.useRunClock(_:) public.

    Gap G2 (Router, not pushed): local Router 7b04bdd9 adds SessionEvent.workStarted and .workEnded (BREAKING). It is not on origin/main. When it is pushed, the exhaustive switch in ScenarioRunner.streamTurn breaks again.

    Count: the tests have 53 .timeLimit traits (27 root, 26 IntegrationTests) and 17 more mentions in comments, not 83.
  timestamp: 2026-10-14T19:15:58.825393+00:00
position_column: done
position_ordinal: ffffde80
title: 'Mail step 5 T0: check Router steps 2 to 4 from Multitool and list each break'
---
Step 5 of the mail work. Read first: /Users/wballard/github/swissarmyhammer/mailbox.md (sections 3, 4 and 5, the signals table, section 8 rows 2 to 5, and the Progress table). All items in mailbox.md are decisions.

## Work
- Resolve the packages. Use the heads that Multitool depends on. Current heads (all on main): Router 2edb4a11 (code as 6cb38629), Extras b68a5d4 (RunClock, ManualRunClock, TelemetryCapture.Context.wait(until:)), Agents ed5bfa2, ACPAgent 021cfaf.
- Build Sources, Tests, the ScenarioGrading product and IntegrationTests.
- Make a list of each break.
- Report each gap in the public API (Router, Extras, Agents) to the step 5 owner before you change code for that gap.

## Changes in Router (step 2 and later)
- All input is Mail with a MailID, through mail(_:). respond(to:), streamEvents(to:) and streamResponse(to:) are helpers over mail(_:).
- streamSessionEvents() gives SessionOutput (event and origin).
- Run events (runMessage, runSettled, runProgress, elicitationRequested) have the origin .mail([id]) of their run mail.
- Each mail id gets one terminal: answered, answerFailed, cancelled or lost.
- messageIds is now mailIds (all delivered mail, run mail also).
- The signals cancel(id), cancelAll(), replace and compact() return their id immediately.
- drain(), cancel() and cancel(message:) are removed.
- awaitAnswer(of:) gives the answer or the original error. awaitTerminal(of:) and awaitAnswer(of:) throw TerminalLookupError for an id that the session does not know.
- An elicitation answer is also mail and starts one more answer (section 4, "Decisions on mail kinds").
- RoutedSession as a type is `any RoutedSession`.
- The run plane is RunPlane. SessionMailbox is removed.

## Rules
- Write all text (comments, docs, commits, reports, tasks) in STE.
- Commit after the task, with Multitool green. Report to the step 5 owner: the commit, the test result, and each difference from the plan with its reason. Do not push until the owner accepts step 5.
- Run the full suite one time. Do not run tests again and again to find a failure. A test that fails only sometimes is a bad test: find the cause and make it deterministic, or fix the race in the code. Do not use .timeLimit, sleep, clock wait, poll or retry. A clock can stay only to measure and print elapsed time, never to wait. If a test hangs, take `sample <pid>` of your own test process before you stop it. Stop only your own process ids (never pkill or a pattern kill).
- Ask the owner before a decision that is not in the plan. Do not delete a test without the decision of the owner.

#mail-step-5