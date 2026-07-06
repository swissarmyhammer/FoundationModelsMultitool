---
comments:
- actor: claude-code
  id: 01kwvzfywx6yypzs9t150tadvk
  text: 'Picked up by /finish (scoped-batch, no filter). Starting iteration 1: delegating to /implement.'
  timestamp: 2026-07-06T15:07:06.525072+00:00
- actor: claude-code
  id: 01kwvzhsm3pcx13fydxjmz49he
  text: 'Picked up by /finish (scoped-batch, no filter). No prior comments. Starting iteration 1: delegating to /implement.'
  timestamp: 2026-07-06T15:08:06.659750+00:00
- actor: claude-code
  id: 01kww02dk9m93z6978ks8e0dng
  text: |-
    Implemented: deleted DirectToolCall.swift and DirectToolCallTests.swift. Removed callTool/directTools/directCallSession plumbing from MultiToolAgent.swift (dispatchCallTool, unknownDirectToolMessage, directCallUnavailableMessage, indexDirectTools, ToolDescriptions.callTool, both public/internal/private initializers' directTools params). Since AgentStep.callTool/AgentTurn.Kind.callTool were the only reason callTool existed as a concept, also removed them from AgentTurn.swift and TurnFormat.swift (both TolerantParseTurnFormat and GuidedTurnFormat), and updated downstream consumers: CLIRunner.swift's trace describe(_:), TranscriptAnalyzer.swift's runCodeStepsBeforeFinal, and the AlwaysFinalTurnFormat test fixture. Cleaned up stale doc comments in ResultRenderer.swift (made `serialize` private, its only external caller was the deleted callTool dispatch) and ToolAPIRenderer.swift, and rewrote docs/SECURITY.md's escape-hatch section.

    Reviewed MultiTool.Registry (MultiTool.swift): affordances/isDirectMode/supportsFindAPIs never had callTool-specific logic (affordances only ever returned ["runCode"] or ["runCode","findAPIs"]) — nothing to remove there; existing MultiToolExecutionTests already assert the callTool-free affordances list.

    grep across Sources/ and Tests/ (including the gated IntegrationTests target) confirms zero remaining references to callTool/CallTool/DirectToolCall/directTools/DirectCallSession/supportsDirectCall.

    swift build: green. swift test: 237 tests passed, 0 failures (gated/live-model suites skipped as expected, same as before this change). Adversarial double-check agent dispatched for sign-off.
  timestamp: 2026-07-06T15:17:11.401978+00:00
- actor: claude-code
  id: 01kww07k4rtstvx09p67kcyx4z
  text: |-
    Adversarial double-check (via double-check agent): PASS, no findings. Independently re-ran `swift build` and `swift build --build-tests` (the latter also compiles the gated FoundationModelsMultitoolIntegrationTests target) — both green. Confirmed exhaustive switches over AgentStep/AgentTurn.Kind with no leftover default masking, no orphaned helpers (indexDirectTools/unknownDirectToolMessage/directCallUnavailableMessage all fully deleted, not just unreferenced), initializer parameter lists consistent across all three MultiToolAgent inits, formatInstructions signature consistent across protocol/both conformers/test fixture/all call sites, and MultiTool.Registry's affordances/isDirectMode/supportsFindAPIs confirmed to have never had callTool-specific logic.

    All acceptance criteria met:
    - DirectToolCall.swift + DirectToolCallTests.swift deleted.
    - MultiToolAgent.swift compiles, existing tests pass, callTool path/directTools removed.
    - Zero remaining callTool/DirectToolCall/directTools references outside this comment/kanban history.
    - MultiTool.Registry surface reviewed (nothing to remove — was already clean).
    - swift build + full swift test green (237 tests passed, gated suites skipped as before).

    Leaving in doing for /review.
  timestamp: 2026-07-06T15:20:00.920022+00:00
- actor: claude-code
  id: 01kww0875drb8nnfwbywmjsddg
  text: 'Implement complete: DirectToolCall.swift + its test file deleted; MultiToolAgent.swift''s dispatchCallTool/directTools/callTool turn-handling removed; AgentStep.callTool/AgentTurn.Kind.callTool also removed from TurnFormat.swift/AgentTurn.swift since they existed only to support this; downstream consumers (CLIRunner, TranscriptAnalyzer, test fixtures) updated; docs/SECURITY.md escape-hatches section rewritten. MultiTool.Registry surface reviewed — no callTool-specific logic found there, nothing to remove. swift build/test green (237 passed), adversarial double-check PASS. Task left in doing per implement''s contract. Proceeding to /test.'
  timestamp: 2026-07-06T15:20:21.421799+00:00
- actor: claude-code
  id: 01kww0bgjghdhd3xt0n1d77k5x
  text: '/test verification: swift build + swift test all green. 237 tests passed in FoundationModelsMultitoolTests, 11 integration tests skipped by pre-existing gating (require live model). No failures, no fixes needed. Grep confirms zero remaining DirectToolCall/callTool references in Sources/ or Tests/. Proceeding to /commit checkpoint.'
  timestamp: 2026-07-06T15:22:09.360091+00:00
position_column: doing
position_ordinal: '8180'
title: Retire callTool/DirectToolCall escape hatch — native tool-calling subsumes its purpose
---
## What
Part of the MultiToolAgent removal pivot (see board). `Sources/FoundationModelsMultitool/Agent/DirectToolCall.swift` exists today as `plan.md`'s escape hatch: a way for `MultiToolAgent`'s main loop to call one direct tool with a schema-valid argument guarantee (via a separate guided-generation grammar derived from that tool's own schema), bypassing `runCode`'s free-JS-argument path — because the hand-rolled ReAct loop's `callTool` action otherwise only ever produced a plain-language `task` description, never guaranteed-valid literal arguments.

With the pivot to Apple's real native `LanguageModelSession(tools:)` tool-calling (backed by a Router-resolved model via the `MLXLanguageModel` adapter, once the upstream multi-turn fix lands — tracked as `mlx-swift-lm`'s own task, short_id `qp8q4h9`), **every** tool registered directly with the session — not just a hand-picked subset — already gets schema-valid, guaranteed-correct argument generation as a basic property of native tool-calling itself. There is no longer a distinct "schema-guaranteed direct call" tier to escape into: it's now the *default* for any tool the session dispatches natively.

This task makes the explicit decision (per the plan's finding that this needs a firm call, not silent ambiguity): **retire `callTool`/`DirectToolCall` entirely.** Delete `Sources/FoundationModelsMultitool/Agent/DirectToolCall.swift` and its test coverage (`Tests/FoundationModelsMultitoolTests/DirectToolCallTests.swift`), and the `directTools`/`callTool` affordance metadata on `MultiTool.Registry` that existed solely to support it.

**IMPORTANT — `MultiToolAgent.swift` is NOT deleted until a later task (`7840f24`), and this task is NOT gated behind that deletion.** `MultiToolAgent` still calls `DirectToolCall.call(tool, task:, using: directCallSession)` directly (its `dispatchCallTool` method), holds a `directTools`/`indexDirectTools` constructor path, and references `ToolDescriptions.callTool`. Deleting `DirectToolCall.swift` in this task WILL break `MultiToolAgent.swift`'s compile unless you also update it here: remove `dispatchCallTool`/the `callTool` turn-handling branch (and its `directTools` plumbing/constructor parameter) from `MultiToolAgent` now, leaving it building and passing its existing tests with `callTool` support gone — `MultiToolAgent.swift` itself is fully deleted later in `7840f24`, but it must compile and its remaining tests must pass at the end of *this* task.

If a caller wants a tool NOT meant for JS-snippet composition (rare — most wrapped tools are meant to be called from `runCode`), the answer going forward is: don't route it through `MultiTool`'s registry at all — register it as its own separate `Tool` directly with `LanguageModelSession(tools:)`, alongside `multiTool` and `findAPIsTool`. No dedicated Multitool-side mechanism is needed for this.

## Acceptance Criteria
- [ ] `DirectToolCall.swift` and its dedicated test file are deleted.
- [ ] `MultiToolAgent.swift` is updated (not just left broken) to compile and pass its existing tests with the `callTool` turn-handling path, `directTools` plumbing, and `ToolDescriptions.callTool` removed.
- [ ] No remaining references to `callTool`/`DirectToolCall`/`directTools` exist outside historical doc-comment mentions (e.g. "formerly supported callTool") — grep confirms no live code path.
- [ ] `MultiTool.Registry`'s public surface (`affordances`, `isDirectMode`, `supportsFindAPIs`) is reviewed: if any of it existed only to support `callTool`, remove it; if it's purely about `findAPIs` vs. direct/no-discovery mode, keep it (that distinction is independent of this decision).
- [ ] `swift build` and full `swift test` remain green.

## Tests
- [ ] Confirm no test file references `DirectToolCall`/`callTool` after deletion (`grep -rn "DirectToolCall\|callTool" Sources/ Tests/` returns only historical prose, if anything).
- [ ] `MultiToolAgentTests.swift`'s existing coverage (minus whatever tests were specifically about `callTool`, which should be removed) still passes.
- [ ] Full `swift test` passes with no regressions.

## Workflow
- Use `/tdd` where applicable — this is primarily a deletion task; verify the full suite stays green after removal, and add/adjust any test asserting `MultiTool.Registry`'s surviving affordance metadata (e.g. `affordances == ["runCode", "findAPIs"]` without a `callTool` entry) if such a test doesn't already exist independent of `callTool`.
