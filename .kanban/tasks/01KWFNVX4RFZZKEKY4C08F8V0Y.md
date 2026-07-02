---
comments:
- actor: wballard
  id: 01kwhtnw80raf6mt9gm9ntzxsp
  text: |-
    Implementation landed and green: `swift build` clean (no warnings in new code), `swift test` 130/130 passing (104 pre-existing + 26 new: 9 in MultiToolAgentTests, 17 in TolerantParseTurnFormatTests).

    Files created:
    - Sources/FoundationModelsMultitool/Agent/AgentSession.swift — internal `AgentSession` protocol (`respond(to:) async throws -> String`) + `RoutedAgentSession` production adapter wrapping a real Router `RoutedSession`.
    - Sources/FoundationModelsMultitool/Agent/TurnFormat.swift — `AgentStep`, `TurnParseError`, the `TurnFormat` protocol, and `TolerantParseTurnFormat` (the ReAct-style `ACTION:`/`TASK:`/`CODE:`/`ANSWER:` lenient parser) + `.tolerantParse(maxRepairTurns:)` static factory.
    - Sources/FoundationModelsMultitool/Agent/MultiToolAgent.swift — the loop itself, `MultiToolAgentError`, fixed runCode/findAPIs instruction blocks (direct-mode aware), librarian dispatch.
    - Test files: MultiToolAgentTests.swift (loop scenarios per every AC), TurnFormatTests.swift (parser unit tests), Fixtures/MultiToolAgentFixtures.swift (ScriptedAgentSession + a second TurnFormat conformer proving the strategy seam).

    Router API resolution: plan.md's description of `RoutedLLM`/`RoutedSession`/`LanguageModelProfile` was verified directly against the checked-out package source at .build/checkouts/FoundationModelsRouter — confirmed accurate (RoutedLLM = RoutedModel<any LoadedLLMContainer>, RoutedSession is a protocol with plain respond(to:)/streamResponse(to:)/fork(workingDirectory:), RoutedLLM.makeSession(instructions:workingDirectory:) is synchronous and non-throwing). No stale-plan surprises this time; findings matched plan.md exactly.

    Ran review (mcp__sah__review) twice; fixed all confirmed findings (doc-comment single-sentence-summary/period rules, runCode/runCodeDirectMode duplication extracted into one parameterized function, TurnFormat.swift field-marker/action-verb literals extracted into named enums, an unused `instructions` stored property removed). Third review pass: 0 findings.

    Deliberately did NOT apply two review suggestions from an earlier pass (both style-only, not bugs, and both re-checked clean on the next review pass anyway):
    1. Labeling `MultiToolAgent`'s first `registry` parameter — kept `_ registry:` unlabeled because it matches plan.md's own documented usage sample (`MultiToolAgent(registry, model: profile.standard, ...)`) verbatim, and the kanban task card's own literal API spec (`MultiToolAgent(registry, model: RoutedLLM, librarian: RoutedLLM?, instructions: String)`).
    2. Labeling `TurnFormat.parseTurn(_ raw:)`'s first parameter — kept unlabeled to match the existing codebase convention (`ToolInvoker.invoke(_ tool: T, content:)`, `ResultRenderer.render(_ result:...)`/`render(_ error:)`).

    Also did a genuine red/green regression check (not just written-then-passing): temporarily broke the repair-turn-budget guard and the max-turns loop bound, reran MultiToolAgentTests, confirmed both broke in exactly the expected tests with the expected failure messages, then reverted — confirms the tests actually exercise the loop's bounding logic, not tautologically.

    Adversarial double-check agent launched against the working diff; awaiting its verdict before final handoff.
  timestamp: 2026-07-02T16:30:33.216351+00:00
- actor: wballard
  id: 01kwhvve1t7hbbeckpzy3mqq7n
  text: |-
    Adversarial double-check (via really-done) returned REVISE with two findings, both fixed:

    1. **Real bug**: `repairsUsed` in `MultiToolAgent.respond(to:)` was a cumulative-per-call counter, not the "consecutive" counter its own doc comments (`TurnFormat.maxRepairTurns`, `MultiToolAgentError.unparseableTurn`) promised. A turn sequence with one recoverable parse hiccup, several successful turns, then one later unrelated hiccup would incorrectly throw with the default budget of 1. Fixed by resetting `repairsUsed = 0` after every successfully parsed turn. Added a regression test (`repairBudgetResetsAfterASuccessfulTurn`) and verified genuine red/green: reverted the fix, confirmed the new test fails with exactly the predicted error ("turn 3... exhausting its repair-turn budget"), then restored the fix and confirmed green.
    2. **Doc-comment gap**: `TurnParseError.description` and `MultiToolAgentError.description` were undocumented, breaking this repo's established convention (every other `CustomStringConvertible.description` in the codebase carries a doc comment). Added matching doc comments to both.

    Then ran mcp__sah__review two more times: fixed a `"```"` code-fence-marker duplication (extracted `FieldMarker.codeFence`); declined to apply a follow-up suggestion to extract "findAPIs"/"runCode" *display*-case literals into constants shared with the lowercase `ActionVerb` matching constants — these display strings are stable, plan.md-mirrored prompt text (also duplicated verbatim in `MultiToolAgent.swift`'s `ToolDescriptions` and various doc comments by design), and coupling them to the case-insensitive matching enum would blur two genuinely different concerns for a two-line saving. Final `mcp__sah__review` pass after that: only those two low-value nitpicks remained, both consciously not applied.

    Final verification: `swift build` clean (no warnings in package code), `swift test` 131/131 passing (104 pre-existing + 27 new: 10 MultiToolAgentTests, 17 TolerantParseTurnFormatTests). All acceptance criteria met:
    - [x] scripted findAPIs → runCode → final dispatch, returns final text
    - [x] malformed turn triggers configured repair turns (default 1) before failing
    - [x] runCode error fed back, corrected second snippet succeeds
    - [x] loop terminates at max-turns with typed error, never spins
    - [x] directMode: findAPIs rejected with instructive message (and no-librarian case too)
    - [x] turn-strategy seam compiles with a second strategy slot (proven via `AlwaysFinalTurnFormat` fixture, no changes to MultiToolAgent/TurnFormat needed)

    Ready for /review. Leaving in doing per implement workflow (not moving to review myself).
  timestamp: 2026-07-02T16:51:03.866056+00:00
depends_on:
- 01KWFNVC3SA55SBZMCCWW6994C
position_column: doing
position_ordinal: '80'
title: 'M4b: MultiToolAgent loop — AgentSession seam + tolerant parse'
---
## What
Per plan.md "Router integration / The agent loop is ours to build" + M4: the tool loop the Router does not provide. (The guided turn format is split out to M4c; this task ships the loop with the tolerant-parse strategy.)
- `Sources/FoundationModelsMultitool/Agent/MultiToolAgent.swift` — `MultiToolAgent(registry, model: RoutedLLM, librarian: RoutedLLM?, instructions: String)`; `respond(to:) async throws -> String` runs the loop: session turn → parse `findAPIs(task)` / `runCode(code)` / final answer → dispatch → feed the result back → repeat, under a bounded max-turn count. Turn strategy is pluggable (`turnFormat`), with `.tolerantParse` implemented here and `.guided` arriving in M4c.
- `Sources/FoundationModelsMultitool/Agent/AgentSession.swift` — a minimal internal seam (protocol) the agent drives, satisfied by Router's `RoutedSession` (plain + guided paths), so unit tests use a scripted fake with zero GPU.
- Tolerant parse: ReAct-style prompted convention + lenient extractor; a parse failure triggers a bounded number of repair turns (configurable, default 1 — the knob lands in M10's `MultiToolConfiguration`) before failing the loop.
- `runCode`/`findAPIs` fixed description strings (the plan's "two tools as the main model sees them") live here as the loop's instruction block; honor `directMode()` (no findAPIs).
- Feed ResultRenderer's repairable errors back as the next turn (M5 repair loop mechanics).

## Acceptance Criteria
- [ ] With a scripted fake session emitting findAPIs → runCode → final, the agent dispatches each correctly and returns the final text
- [ ] A malformed turn triggers the configured number of repair turns (default 1) before failing the loop
- [ ] A runCode error result is fed back and a corrected second snippet succeeds (scripted)
- [ ] The loop terminates at max-turns with a typed error, never spins
- [ ] directMode: findAPIs from the model is rejected with an instructive message
- [ ] The turn-strategy seam compiles with a second strategy slot (M4c plugs in without touching loop semantics)

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/MultiToolAgentTests.swift` — scripted-fake-session scenarios above under `.tolerantParse`
- [ ] `swift test --filter MultiToolAgentTests` → passes

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.