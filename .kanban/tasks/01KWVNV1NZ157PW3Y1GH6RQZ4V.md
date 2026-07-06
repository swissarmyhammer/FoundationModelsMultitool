---
position_column: todo
position_ordinal: '8480'
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
