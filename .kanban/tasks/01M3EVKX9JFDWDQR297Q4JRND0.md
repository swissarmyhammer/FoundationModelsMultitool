---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3f2mh1w4z01j2amhrmqs414
  text: 'User decision (2026-09-26): `MultiToolConfiguration.defaultInlineSettleGrace` is 30 s. This is already done in the working tree. Do not make this default smaller to obey generation-queue.md §5.5 rule 5. The subtask "Check `inlineSettleGrace` against rule 5" is closed by this decision. Only document the cost: a long snippet holds the model for up to 30 s. `SuspendedContextTests.everyMountedCallAnswersThePendingEnvelope` and the parked `MCPSessionSweepTests` case now set `inlineSettleGrace: 0` explicitly.'
  timestamp: 2026-09-26T14:41:47.068426+00:00
- actor: claude-code
  id: 01m3f363ch0jcnr30tebxsbat6
  text: 'Correction (2026-09-26): this replaces the 30 s comment above. The user decision is now `MultiToolConfiguration.defaultInlineSettleGrace` = 5 s, and this is done in the working tree. Do not change this default in this task. The subtask "Check `inlineSettleGrace` against rule 5" is closed by this decision. `SuspendedContextTests.everyMountedCallAnswersThePendingEnvelope` and the parked `MCPSessionSweepTests` case keep `inlineSettleGrace: 0`: the first has a 3 s response bound, which is less than 5 s.'
  timestamp: 2026-09-26T14:51:22.897820+00:00
- actor: claude-code
  id: 01m3fg9rq54v2348n6zgw5jqeq
  text: |-
    Research (implement, iteration 1):
    - Router c208add `BackgroundToolRunner.settledEnvelope` withdraws the staged events of a run that settles inside `inlineSettleGrace` (`withdrawStagedEvents`). Thus an inline result is not also mail.
    - `SessionMailbox.wait(completionToken:seconds:)` withdraws nothing. Thus a run that the sandbox `wait()` global collects is ALSO staged as mail. This is the double delivery. The test in `MultiToolExecutionTests` records it; the follow-up task ^f11cfnx0 (remove the sandbox `wait()`) removes that path.
    - Model-facing text that names the wait tool: `MultiTool.collectInstruction`, `MultiTool.resultInstruction`, the `runCode` description, `Execute.collectInstruction` and the `execute` description (`Capabilities/Shell/Execute.swift`). All change.
    - `RunState`, `CallResult`, `terminalEventFields`, `tokenOnlyFields` were internal only for `WaitTool`. After the removal only `MultiTool+SandboxGlobals.swift` uses them, so they become file-private.
    - IntegrationTests (separate package) names `WaitTool` in `Support/ScenarioRunner.swift:918,1137` and uses `InBandCollectionEvidence`. Task ^ER9Z (01M3ETVQGBG0R25ED1ER77ER9Z) owns that change. That package does not compile after this task until that task is done.
    - The CLI demo drives `streamEvents(to:)` and prints the first answer only. A mail answer goes to `streamSessionEvents()`. A new task records this.
  timestamp: 2026-09-26T18:40:34.533467+00:00
- actor: claude-code
  id: 01m3fgzc3cdkmc62tsympwedqj
  text: |-
    Double delivery check (subtask 3), result: YES, a run that the sandbox `wait()` global collects is ALSO delivered as mail. Test `MultiToolExecutionTests.runCollectedBySandboxWaitIsAlsoMail`: a gated snippet outlasts a 1 s grace and answers pending; a second snippet collects it with `wait(token, 10)` and gets the result inline; after the answer, exactly one mail submission still carries the same result. Cause: Router `SessionMailbox.wait(completionToken:seconds:)` withdraws no staged event; only `BackgroundToolRunner.settledEnvelope` (the inline settle grace) withdraws it. Task ^11cfnx0 removes the sandbox `wait()` and with it this second path. A run that settles inside the inline grace is NOT mail (withdrawn), and a run that settles after the answer comes back as exactly one mail submission (`settledRunComesBackAsOneMail`).

    Test fixture fact: Router keeps loaded models in the process-wide `ModelPool.shared` by `ModelRef`. A stub session with its own container needs a fresh `standard` reference, else it gets the container of an earlier test (`makeStubProfile(standardModel:)`).

    IntegrationTests note: the separate IntegrationTests package still names `WaitTool` (`Support/ScenarioRunner.swift:918,1137`) and uses `InBandCollectionEvidence` / `inBandCollectionChecks` / `noBackgroundRunsAtAnswerCheckName` / `noBackgroundRunsAfterRespondCheckName`, which this task replaced with `MailCollectionEvidence` / `mailCollectionChecks` / `mailCollectionCheckName` / `noBackgroundRunsAtLastAnswerCheckName` in `Tests/Support/ScenarioGrading`. That package does not compile until task ^ER9Z (01M3ETVQGBG0R25ED1ER77ER9Z) is done.

    New task ^18s996p: the CLI demo prints only the first answer; the answer that mail starts goes to `streamSessionEvents()`.

    ### implement — changed
    - evidence: WaitTool.swift + WaitToolTests.swift deleted; MultiTool.swift, MultiTool+Background.swift, MultiTool+SandboxGlobals.swift, MultiToolConfiguration.swift, Capabilities/Shell/Execute.swift, Capabilities/Shell/GetLines.swift, Diagnostics/CallTrace.swift, MultitoolCLI/CLIRunner.swift; tests: MultiToolExecutionTests, RouterSessionMountTests, InlineSettleGraceTests, ScenarioGradingTests, ScenarioFixtureTests, Fixtures/MailProbeFixtures.swift (new), Fixtures/StubRouterFixtures.swift, Support/ScenarioGrading/{ScenarioGrading,ScenarioTools,ScenarioCallLog}.swift
    - next: test, commit, review
  timestamp: 2026-09-26T18:52:22.508650+00:00
- actor: claude-code
  id: 01m3fgzyhbn1kchncy7th68zcj
  text: |-
    ### test — green
    - evidence: `swift build --build-tests` clean (0 warnings); `swift test` — 1786 tests in 144 suites passed, 0 failed, 0 skipped. One earlier run had a failure in `ResilienceTests.freshOperationWaitsForInFlightDisconnectStragglerBoundedByDisconnectGracePeriod` (MCP disconnect timing, code this task does not touch); it passed 3 times alone and in the next full run.
    - next: commit
  timestamp: 2026-09-26T18:52:41.387178+00:00
- actor: claude-code
  id: 01m3fhh71be25y05xqjfy37dgs
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — WaitTool removed, model-facing text now says end the answer / result comes back as mail, mail tests added, ScenarioGrading canary moved to mail collection
    - test: green — `swift test` 1786 passed, 0 failed, 0 skipped; build 0 warnings
    - commit: changed — d2d1e2b feat(mcp)!: remove the wait tool; a settled background run comes back as mail
    - review: findings — 1 finding (review sha HEAD~1..HEAD): Tests/FoundationModelsMultitoolTests/Fixtures/MailProbeFixtures.swift:112 code-hygiene/disallowed-constructs-swift no_unchecked_sendable
  timestamp: 2026-09-26T19:02:07.147628+00:00
depends_on:
- 01M3EVK4VR545ABV6R9YHFQH76
position_column: review
position_ordinal: '80'
title: 'Remove the wait tool: a settled background run comes back as mail'
---
## What
User decision (2026-09-26): remove `wait`, and use mail. The Router design (`../FoundationModelsRouter/generation-queue.md` §5.5) says that an in-band tool body holds the model for every session on it, and a settled background run comes back to the session as mail between two submissions. The top-level `wait` tool (`Sources/FoundationModelsMultitool/WaitTool.swift`) is an in-band hold that has no bound after the pin move. Its doc also describes removed behavior: `respond(to:)` "collects", `backgroundRunDrainRoundLimit`, and `dispatchNextPrompt()`.

- [x] Delete `Sources/FoundationModelsMultitool/WaitTool.swift` and `Tests/FoundationModelsMultitoolTests/WaitToolTests.swift`. Remove `WaitTool()` from `MultiTool.Builder.makeSessionToolsAndStaging` (`Sources/FoundationModelsMultitool/MultiTool.swift`, both branches) and from any other mount list.
- [x] Rewrite the model-facing text that tells the model to call `wait`: the background envelope's `next` sentence (`MultiTool+Background.swift`, `RouterSessionMountTests.swift:112-122`), `collectInstruction`, and the `runCode` / `searchTools` descriptions. The new text says: end your answer, and the result comes back as a new message when the run finishes.
- [x] Check with a test whether a run collected in any other way is also delivered as mail (double delivery). Record the result in a task comment.
- [x] Check `MultiToolConfiguration.inlineSettleGrace` against §5.5 rule 5 (keep it small, because it holds the model). Change the default if it is larger than the rule allows, and state the reason in its doc comment.
- [x] Update `Tests/Support/ScenarioGrading` rules that expect a `wait` call (`ScenarioGrading.swift`, 5 uses).

## Acceptance Criteria
- [x] `rg -w 'WaitTool|backgroundRunDrainRoundLimit|dispatchNextPrompt' Sources Tests` returns no match.
- [x] No mounted tool list contains a tool named `wait`.
- [x] The background envelope text does not name a `wait` tool, and it tells the model to end its answer.
- [x] `swift test` passes.

## Tests
- [x] `Tests/FoundationModelsMultitoolTests/RouterSessionMountTests.swift`: the envelope `next` text says to end the answer and does not contain "wait tool".
- [x] `Tests/FoundationModelsMultitoolTests/MultiToolExecutionTests.swift`: with a stub session, a background `runCode` that settles after the answer causes one mail submission that contains the result, and exactly one.
- [x] Run `swift test`. Expected result: all tests pass.

## Workflow
- Use `/tdd`. Write failing tests first, then do the implementation that makes them pass.

## Review Findings (2026-09-26 13:52)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 20 file(s) reviewed, 4 not reviewed.

- [x] `Tests/FoundationModelsMultitoolTests/Fixtures/MailProbeFixtures.swift:112` `code-hygiene/disallowed-constructs-swift` — no_unchecked_sendable: Instead of @unchecked Sendable, write a plain Sendable conformance or a @preconcurrency import. If the type really must be @unchecked Sendable, write // swiftlint:disable:next no_unchecked_sendable above it with the synchronization invariant that makes the type thread-safe.