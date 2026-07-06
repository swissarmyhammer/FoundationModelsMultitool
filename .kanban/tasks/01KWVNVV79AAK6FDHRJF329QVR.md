---
depends_on:
- 01KWVNTEAPVS13BB8H04AVEEPP
position_column: todo
position_ordinal: '8580'
title: Build the canonical Router + LanguageModelSession + MultiTool example, replacing multitool-cli's MultiToolAgent-based demo
---
## What
Part of the MultiToolAgent removal pivot (see board). Depends on `4aveepp` (`findAPIsTool` must exist as a standalone `Tool`).

**Known external blocker**: this task's end-to-end multi-tool-call behavior depends on `mlx-swift-lm`'s own task `qp8q4h9` ("Fix MLXLanguageModel's tool-calling to delegate to FoundationModels' own multi-turn session machinery") landing upstream — today, `MLXLanguageModel`'s tool-calling caps at one native tool call per session turn (a continuation round after a tool result falls through to plain text). Build this task's code against the *target* multi-turn-capable interface regardless; if the upstream fix hasn't landed when this is implemented, the new gated test (`k4mj1gm`, see board) will surface exactly that as a real, correctly-scoped failure — don't design around the bug permanently, and don't block starting this task on the fix landing first (the plumbing — Router resolve, adapter construction, session wiring, CLI argument handling — is all independent of whether multi-turn tool-calling works yet).

**Package.swift dependency**: `MLXLanguageModel` is a product of `MLXFoundationModels`, part of the `mlx-swift-lm` fork already pinned to the `mlx-foundationmodels` branch (`mlxPackage` in `Package.swift`) — but no target currently links the `MLXFoundationModels` product itself (`liveLoaderMLXProducts` only declares `MLXLMCommon`/`MLXHuggingFace`). Add `.product(name: "MLXFoundationModels", package: mlxPackage)` to the `multitool-cli` executable target's dependencies.

Rebuild `Sources/multitool-cli` (`CLIRunner.swift`, `DemoTools.swift`, `main.swift`) around:
1. `Router.resolve(profile)` → a resolved `LanguageModelProfile` (same as today).
2. Wrap the resolved generation model as a real `FoundationModels.LanguageModel` via `MLXLanguageModel` (check exactly how to obtain the `ModelConfiguration`/`ModelContainer` a resolved `RoutedLLM`/`LanguageModelProfile` already holds, so this doesn't re-resolve or re-download; `MLXLanguageModel`'s own doc comment shows the shape: `MLXLanguageModel(configuration:capabilities:weightsLocation:load:)`).
3. Construct a real `FoundationModels.LanguageModelSession(model: mlxLanguageModel, tools: [multiTool, findAPIsTool], instructions: ...)`.
4. Call `session.respond(to: demoPrompt)` and print the answer — Apple's own native tool-calling loop decides when to call `findAPIs` vs `runCode`, no hand-rolled turn parsing.
5. `findAPIsTool`'s own internal selection tier (per task `4aveepp`) is backed by a *separate* Router-resolved `RoutedSession` (e.g. `profile.flash`), independent of the main `LanguageModelSession` — mirrors the old "librarian on flash" split.

**Decided**: the `--direct` flag now means "register only `multiTool` with the session, omitting `findAPIsTool`" (the model discovers tools via `help()`/`docs(name)` in-snippet instead) — this preserves its original intent (skip the discovery round-trip) under the new tool-registration model. Implement it this way; do not leave this as an open decision.

**Decided**: remove the old turn-trace reading logic (`traceLines`/`describe` in `CLIRunner.swift`, which parsed `AgentStep`s out of a Router-recorded transcript via `TurnFormat`) entirely — do not attempt to build an equivalent trace feature against `LanguageModelSession`'s own transcript for this task; just print the final answer. A trace feature can be a future addition if wanted, not a requirement here.

## Acceptance Criteria
- [ ] `Package.swift`'s `multitool-cli` executable target links `.product(name: "MLXFoundationModels", package: mlxPackage)`.
- [ ] `multitool-cli` builds and runs against `MULTITOOL_INTEGRATION`-style live hardware (same gating convention as today), resolving a model via Router, backing a real `LanguageModelSession`, and printing an answer to the demo prompt.
- [ ] `--direct` registers only `multiTool` with the session (no `findAPIsTool`), per the decision above.
- [ ] No references to `MultiToolAgent`/`TurnFormat`/`AgentStep`/`AgentTurn` remain in `Sources/multitool-cli`.
- [ ] `CLIArgumentTests.swift`'s no-model unit coverage (argument parsing, Router-unavailable degrade path) still passes, adapted for whatever the new `run(...)`/`runDemo(...)` shape becomes.
- [ ] `swift build` succeeds.

## Tests
- [ ] Update `Tests/FoundationModelsMultitoolTests/CLIArgumentTests.swift` for the new `CLIRunner` shape — argument parsing and the Router-unavailable degrade path must still be unit-testable with no live model.
- [ ] A new or adapted gated smoke test (mirrors today's `CLISmokeTests.swift`, but exercises the new `LanguageModelSession`-based path) — see the `k4mj1gm` task for the broader gated-suite migration; this task's own acceptance is satisfied once the CLI itself works, full gated-suite verification is that other task's job.
- [ ] `swift test` (ungated) passes.

## Workflow
- Use `/tdd` for the argument-parsing/degrade-path unit tests. The live end-to-end behavior is necessarily hardware-gated — verify manually on real hardware during implementation, and hand off full automated gating to the dedicated integration-suite-porting task.
