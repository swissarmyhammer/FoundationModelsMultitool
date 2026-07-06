---
depends_on:
- 01KWVNTEAPVS13BB8H04AVEEPP
- 01KWVNVV79AAK6FDHRJF329QVR
position_column: todo
position_ordinal: '8180'
title: Add a canonical-usage ExamplesTests suite, mirroring FoundationModelsRouter/FoundationModelsMetadataRegistry's living-documentation pattern
---
## What
**Rescoped 2026-07-06**: originally written around `MultiToolAgent`'s scripted-session fixtures (see comment history), before the decision to remove `MultiToolAgent` entirely in favor of Apple's native `LanguageModelSession(tools:)` tool-calling (see board — depends on `4aveepp`, `f329qvr`). This task now targets the *new* design.

Both sibling packages give consumers copy-pasteable, tested "how do I…" examples:
- `FoundationModelsRouter`'s `Tests/FoundationModelsRouterTests/ExamplesTests.swift` is a `@Suite("Examples: canonical usage of the public API")` — each `@Test` is a self-contained example whose body reads like real consumer code, running fully offline via injected stubs so it stays green in CI with no network/GPU.
- `FoundationModelsMetadataRegistry` has an analogous `ExamplesSmokeTests.swift` plus a whole `Examples/` directory.

`FoundationModelsMultitool` still has no equivalent. Add `Tests/FoundationModelsMultitoolTests/ExamplesTests.swift`, a `@Suite("Examples: canonical usage of the public API")`, demonstrating the library's core API end to end using the **new** design:

1. **"Author a catalog with `MultiTool.Builder`: standalone and grouped tools"** — unchanged from the original scope; build a small `APISurface` via `.addTool(_:)`/`.addGroup(named:_:)`, assert the rendered surface's shape.
2. **"Register `MultiTool` directly with Apple's `LanguageModelSession`"** — the simplest real integration: construct `MultiTool(registry:)`, hand it to a `LanguageModelSession(tools: [multiTool])` (using whatever offline-stubbable seam `MLXLanguageModel`/`LanguageModelSession` testing requires — check how `FoundationModelsRouter`'s own `ExamplesTests.swift` stubs its seams, e.g. `ExampleHarness`'s canned-container pattern, for a model to follow), and show a tool call round-tripping.
3. **"The `findAPIs` → `runCode` discovery-then-call handoff, via native tool-calling"** — script `findAPIsTool`'s selection tier to pick a specific tool by id, register both `multiTool` and `findAPIsTool` with a `LanguageModelSession`, and show (script) the model calling `findAPIs` then `runCode` in sequence — this is the concrete, tested version of the exact worked example already written out in chat with the user (a `findAPIs("...")` call returning a rendered block, followed by a `runCode` call using the discovered, properly-qualified signature). This example inherently depends on `mlx-swift-lm`'s multi-turn tool-calling fix (`qp8q4h9`) if driven against a *real* model — for the offline example test, script/stub the executor directly so the example doesn't require live hardware or the upstream fix to be green in CI (the example documents the *intended* usage regardless of the current live-hardware caveat).

## Acceptance Criteria
- [ ] `Tests/FoundationModelsMultitoolTests/ExamplesTests.swift` exists, `@Suite("Examples: canonical usage of the public API")`, with at least the three examples above.
- [ ] Every example runs fully offline (no live model, no network, no `MULTITOOL_INTEGRATION` gate) via stubbed seams, matching the sibling packages' own `ExamplesTests` pattern.
- [ ] The `findAPIs` → `runCode` example explicitly asserts on the discovery text handed back (not just the final answer), documenting what the model actually sees between the two steps, including a grouped tool's properly-qualified example call (per task `12rtn85`'s fix).
- [ ] `swift build` and full `swift test` remain green.

## Tests
- [ ] The new `ExamplesTests.swift` suite itself, `swift test --filter ExamplesTests`, all `@Test`s pass.
- [ ] Full `swift test` passes with no regressions.

## Workflow
- Use `/tdd` — write each example test against the real `MultiTool`/`findAPIsTool`/`LanguageModelSession` APIs (with offline stubs), watch it fail first, then adjust until green.
