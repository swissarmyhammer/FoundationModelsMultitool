---
comments:
- actor: claude-code
  id: 01kxgdbq2vm2mr7z5f2gqpp66g
  text: |-
    Implemented. Added Tests/FoundationModelsMultitoolTests/ExamplesTests.swift, a `@Suite("Examples: canonical usage of the public API")` with the three required examples, mirroring FoundationModelsRouter's own ExamplesTests.swift ExampleHarness pattern.

    Research: read FoundationModelsRouter/Tests/FoundationModelsRouterTests/ExamplesTests.swift (the model to follow — its offline `ExampleHarness` stubbing the router's own seams) and FoundationModelsMetadataRegistry/Tests/FoundationModelsMetadataRegistryTests/ExamplesSmokeTests.swift. Also read the new f329qvr/4aveepp work (MultiTool.swift, FindAPIsTool.swift, CLIRunner.swift) that this task documents.

    Key discovery: `FoundationModels.LanguageModelSession(model: some LanguageModel, tools:, instructions:)` on this repo's target platform (real macOS 27 SDK — confirmed via the actual installed Xcode-beta SDK's `.swiftinterface`) accepts *any* conformer of the public `FoundationModels.LanguageModel`/`LanguageModelExecutor` protocol pair, the same pluggable-model seam `MLXLanguageModel` fills in production (`Sources/multitool-cli/CLIRunner.swift`). This meant the offline-stubbable seam for genuinely exercising `LanguageModelSession`'s own native multi-turn tool-calling loop was writing a minimal from-scratch `ScriptedLanguageModel`/`Executor` conformer (the file's only non-production code, mirroring Router's ExampleHarness), rather than needing MLX weights or Apple Intelligence. Its `nextTurn: @Sendable (Transcript) -> ScriptedTurn` closure decides purely by inspecting the transcript's own entries so far (no hidden call-count state) — this let real `MultiTool`/`FindAPIsTool` execution (through the real JS interpreter, and a real scripted `MetadataSearcher`/`SelectionConfig` selection tier reusing `FindAPIsToolTests.swift`'s own `RootSessionRespondCalledDirectlySession` pattern) run genuinely offline. This was built and iterated against the real installed FoundationModels.framework on real Apple Silicon hardware (this environment runs macOS 27), not guessed blind — all 3 examples run and pass for real, exercising Apple's actual native multi-turn tool-calling orchestration.

    One correction made along the way: the original draft reused `GithubCreateIssueTool` (Output: `PlainTextOutput`, only `PromptRepresentable` not `Generable`) for the findAPIs→runCode handoff test, which failed at real runtime — `ArgumentMarshaler.renderOutput` requires a `Generable`-or-`String` Output to render a tool's return value back into the interpreter, and `PlainTextOutput` was only ever a rendering-only fixture (used elsewhere for docs-shape tests, never invoked for real). Switched to `IssueCountTool` from `MultiToolExecutionFixtures.swift` (a real Generable-output grouped tool, already exercised via runCode elsewhere in the suite), keeping the same qualified-path (`tools.github.issueCount(...)`) proof.

    Fixtures reused (no new fixture types beyond the file-local `ScriptedLanguageModel` stub): `WeatherTool`/`GithubCreateIssueTool`/`GithubSearchTool` (BuilderSurfaceFixtures.swift), `TripCitiesTool`/`RootSessionRespondCalledDirectlySession` (MultiToolAgentFixtures.swift), `IssueCountTool` (MultiToolExecutionFixtures.swift).

    Verification (really-done, fresh): `swift build` — exit 0. `swift build --build-tests` — exit 0. `swift test --skip FoundationModelsMultitoolIntegrationTests` — 242 tests passed, 22 suites, 0 failures (including all 3 new ExamplesTests). `swift test --filter ExamplesTests` — 3/3 pass. Adversarial double-check agent: PASS, no findings — confirmed every asserted string traces to real (non-scripted) production code paths, confirmed fixture reuse is accurate and non-duplicative, confirmed style matches Router's ExamplesTests.swift convention, confirmed git diff is exactly the one new file.

    Leaving in `doing` for `/review` per the implement skill's contract.
  timestamp: 2026-07-14T13:34:16.155698+00:00
- actor: claude-code
  id: 01kxgdh7hdg3vee58je60tp0w0
  text: '/test verification (independent subagent): swift build/build-tests/test all green. 242 tests passed (239 baseline + 3 new ExamplesTests), 11 gated skipped, 0 failures. swift test --filter ExamplesTests confirms all 3 examples individually pass. Proceeding to /commit checkpoint.'
  timestamp: 2026-07-14T13:37:16.845110+00:00
depends_on:
- 01KWVNTEAPVS13BB8H04AVEEPP
- 01KWVNVV79AAK6FDHRJF329QVR
position_column: doing
position_ordinal: '80'
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
- [x] `Tests/FoundationModelsMultitoolTests/ExamplesTests.swift` exists, `@Suite("Examples: canonical usage of the public API")`, with at least the three examples above. Verified: the file exists with exactly these three `@Test`s (`authorCatalogStandaloneAndGrouped`, `registerMultiToolWithLanguageModelSession`, `findAPIsThenRunCodeHandoff`).
- [x] Every example runs fully offline (no live model, no network, no `MULTITOOL_INTEGRATION` gate) via stubbed seams, matching the sibling packages' own `ExamplesTests` pattern. Verified: the only non-production code is a file-local `ScriptedLanguageModel`/`Executor` — a minimal conformer of the real `FoundationModels.LanguageModel`/`LanguageModelExecutor` protocol pair (the same pluggable-model seam `MLXLanguageModel` fills in production) whose `nextTurn` closure decides purely from the real `Transcript`'s own state. No `MULTITOOL_INTEGRATION` gate, no network, no MLX weights.
- [x] The `findAPIs` → `runCode` example explicitly asserts on the discovery text handed back (not just the final answer), documenting what the model actually sees between the two steps, including a grouped tool's properly-qualified example call (per task `12rtn85`'s fix). Verified: `findAPIsThenRunCodeHandoff` asserts the discovery text contains `"// tools.github.issueCount"` and the qualified `"tools.github.issueCount("` call, and explicitly asserts the bare `"tools.issueCount("` is absent.
- [x] `swift build` and full `swift test` remain green. Verified fresh: `swift build` exit 0; `swift build --build-tests` exit 0; `swift test --skip FoundationModelsMultitoolIntegrationTests` — 242 tests passed, 22 suites, 0 failures.

## Tests
- [x] The new `ExamplesTests.swift` suite itself, `swift test --filter ExamplesTests`, all `@Test`s pass. Verified fresh: 3/3 passed.
- [x] Full `swift test` passes with no regressions. Verified fresh: 242/242 passed (gated integration suite skipped per project convention, as CLIArgumentTests/others already do).

## Workflow
- Use `/tdd` — write each example test against the real `MultiTool`/`findAPIsTool`/`LanguageModelSession` APIs (with offline stubs), watch it fail first, then adjust until green.
