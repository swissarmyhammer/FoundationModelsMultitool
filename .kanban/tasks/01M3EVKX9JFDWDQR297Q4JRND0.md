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
depends_on:
- 01M3EVK4VR545ABV6R9YHFQH76
position_column: todo
position_ordinal: '8980'
title: 'Remove the wait tool: a settled background run comes back as mail'
---
## What
User decision (2026-09-26): remove `wait`, and use mail. The Router design (`../FoundationModelsRouter/generation-queue.md` §5.5) says that an in-band tool body holds the model for every session on it, and a settled background run comes back to the session as mail between two submissions. The top-level `wait` tool (`Sources/FoundationModelsMultitool/WaitTool.swift`) is an in-band hold that has no bound after the pin move. Its doc also describes removed behavior: `respond(to:)` "collects", `backgroundRunDrainRoundLimit`, and `dispatchNextPrompt()`.

- [ ] Delete `Sources/FoundationModelsMultitool/WaitTool.swift` and `Tests/FoundationModelsMultitoolTests/WaitToolTests.swift`. Remove `WaitTool()` from `MultiTool.Builder.makeSessionToolsAndStaging` (`Sources/FoundationModelsMultitool/MultiTool.swift`, both branches) and from any other mount list.
- [ ] Rewrite the model-facing text that tells the model to call `wait`: the background envelope's `next` sentence (`MultiTool+Background.swift`, `RouterSessionMountTests.swift:112-122`), `collectInstruction`, and the `runCode` / `searchTools` descriptions. The new text says: end your answer, and the result comes back as a new message when the run finishes.
- [ ] Check with a test whether a run collected in any other way is also delivered as mail (double delivery). Record the result in a task comment.
- [ ] Check `MultiToolConfiguration.inlineSettleGrace` against §5.5 rule 5 (keep it small, because it holds the model). Change the default if it is larger than the rule allows, and state the reason in its doc comment.
- [ ] Update `Tests/Support/ScenarioGrading` rules that expect a `wait` call (`ScenarioGrading.swift`, 5 uses).

## Acceptance Criteria
- [ ] `rg -w 'WaitTool|backgroundRunDrainRoundLimit|dispatchNextPrompt' Sources Tests` returns no match.
- [ ] No mounted tool list contains a tool named `wait`.
- [ ] The background envelope text does not name a `wait` tool, and it tells the model to end its answer.
- [ ] `swift test` passes.

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/RouterSessionMountTests.swift`: the envelope `next` text says to end the answer and does not contain "wait tool".
- [ ] `Tests/FoundationModelsMultitoolTests/MultiToolExecutionTests.swift`: with a stub session, a background `runCode` that settles after the answer causes one mail submission that contains the result, and exactly one.
- [ ] Run `swift test`. Expected result: all tests pass.

## Workflow
- Use `/tdd`. Write failing tests first, then do the implementation that makes them pass.