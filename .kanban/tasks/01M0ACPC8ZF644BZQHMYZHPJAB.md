---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0amthv3nmf1sf4zz3yj8wtx
  text: |-
    Research for the combined sweep over ^yzhpjab, ^523qwcy and ^mxjt7y5.

    Facts established:

    - No file in `Sources/` or `Tests/` imports `MLXFoundationModels`, and no file names a symbol from it. Router's own library target already links the product (`../FoundationModelsRouter/Package.swift`, `mlxProducts`), and Router's `Resolution/LiveModelLoader.swift` is the file that is written over `MLXLanguageModel`. So the two direct `.product(name: "MLXFoundationModels", ...)` declarations here are redundant for compile and for link. The card allows "kept with a true reason, or dropped"; the dispatching constraint forbids editing dependency declarations and forbids a gated run, and the dropped-product check is exactly the gated CLI smoke test. So the product stays and both comments are rewritten to state what is true.
    - `muse_glimmer` is registered in `VLMModelFactory` alone (`mlx-swift-lm` `Libraries/MLXVLM/VLMModelFactory.swift`). The pin that ships today, `mlx-community/Qwen3.8-27B-mxfp4`, carries `model_type: qwen3_5`, which is registered in BOTH `LLMModelFactory` and `VLMModelFactory`. `Package.swift`'s `liveLoaderMLXProducts` comment therefore names a model the CLI has not pinned since `1344a51`.
    - `runNativeIntegrationScenario` does NOT build a bare `LanguageModelSession` any more. It builds `fixture.profile.standard.makeSession(tools:discoveryPriming:)`, the same `RoutedSession` `runElevationIntegrationScenario` builds. Both doc comments that justify the second runner by "the native runner has no elevation mount" are stale as of `f8964b4`; the real difference is what each runner asserts.
    - `NativeToolCallEvaluation` (plan.md) names a type that does not exist anywhere in the repository.
    - HEAD is `a5e4587`. The model pin moved to Qwen3.8 at `1344a51`; the CLI moved onto the host contract at `f8964b4`.

    Scope decision for plan.md: the two `makeMLXLanguageModel(for:)` sites and the passages that state the CLI's wiring are corrected to the shipped design. A name that no longer exists may stay only where the text says it is retired — the convention plan.md already uses for `MultiToolAgent`.
  timestamp: 2026-08-18T14:36:21.219449+00:00
- actor: claude-code
  id: 01m0anp2wkj3ze0rqmgjg9jq56
  text: |-
    One sweep covered all three cards. What landed in `Package.swift`:

    - Both `MLXFoundationModels` comments rewritten. The product is **kept** on each target, and the reason each comment now gives is the true one: the target names no symbol of that module, but it does construct Router's `LiveModelLoader`, and that loader is written over `MLXLanguageModel`. The comment says so, and says the module is named here alongside `liveLoaderMLXProducts` so the live-inference set is stated by this target rather than inherited from Router's target list.
    - Dropping the product was the other option the card allowed, and it was rejected on the dispatching constraint, not on preference: this pass must not edit dependency declarations, and the only check that would catch a wrong drop is the gated CLI smoke test, which this pass is forbidden to run.
    - Third instance of the same class, which no card named: the `liveLoaderMLXProducts` `MLXVLM` comment claimed Muse Glimmer is "the model both the CLI demo profile and the gated suite pin". It has not been since `1344a51`. It now states the mechanism without naming a pin, points at `CLIRunner.generationModel` as the one place a model is named, and records that the pin shipping today carries `model_type: qwen3_5`, which both `LLMModelFactory` and `VLMModelFactory` register — so the `MLXVLM` link is what keeps a swap back to a VLM-only checkpoint resolving rather than what today's pin needs.
    - `mlxPackage`'s own doc said "only three of its products are declared directly here" while four are. Corrected, and `MLXFoundationModels` is now named in that list.

    The third acceptance criterion stays unticked, honestly: ungated `swift test` is green (359 tests/30 suites, 59 tests/11 suites), and the gated CLI smoke test was not run because this pass was told not to run one. No MLX product was dropped, so nothing a gated run grades was changed.

    ### implement — changed
    - evidence: `swift test` green — 359 tests in 30 suites, 59 tests in 11 suites, zero failures. Files: Package.swift, README.md, plan.md, docs/SECURITY.md, Sources/FoundationModelsMultitool/{MultiTool.swift, MultiToolConfiguration.swift, Discovery/SearchToolsTool.swift}, Sources/multitool-cli/{CLIRunner.swift, DemoTools.swift}, Tests/FoundationModelsMultitoolTests/ExamplesTests.swift, Tests/FoundationModelsMultitoolIntegrationTests/{ElevationTests.swift, SearchThenCallTests.swift, Fixtures/ScenarioTools.swift, Support/{IntegrationGate.swift, NativeTranscript.swift, ScenarioRunner.swift}}
    - next: review. New work found and filed as `^hgxcy0y` (direct-mode `--help` text says only `runCode` is registered; `wait` is vended too).
  timestamp: 2026-08-18T14:51:23.411056+00:00
position_column: doing
position_ordinal: '8380'
title: Package.swift comments name CLIRunner.makeMLXLanguageModel(for:), which no longer exists
---
`^260yggp` moved `CLIRunner.runDemo` onto a `RoutedSession` and deleted `CLIRunner.makeMLXLanguageModel(for:)`, whose only caller it was. `Package.swift` was under an explicit "do not edit" constraint on that card, so two of its comments still name the deleted symbol:

    Package.swift:199   // the CLI can build a native `LanguageModelSession` directly
                        // over it — see `CLIRunner.makeMLXLanguageModel(for:)`.
    Package.swift:249   // directly, the same way `multitool-cli` itself does (via
                        // `CLIRunner.makeMLXLanguageModel(for:)`) — the gated scenarios

Both comments justify the `MLXFoundationModels` product dependency on the `multitool-cli` executable target and on the gated integration test target. Neither target names an `MLXFoundationModels` symbol any more: `grep -rn "MLXFoundationModels\|MLXLanguageModel" Sources/ Tests/` returns only prose.

## What to decide

- Whether the `MLXFoundationModels` dependency on each of the two targets is still needed at all (the library is reached through `FoundationModelsRouter`, which imports it).
- Rewrite both comments against whatever survives. Do not remove `liveLoaderMLXProducts` — `MLXVLM` is linked for the factory registry, and `CLIRunner.swift` records why.

## Acceptance Criteria

- [x] No comment in `Package.swift` names a symbol that does not exist
- [x] The `MLXFoundationModels` dependency is kept with a true reason, or dropped
- [x] Ungated `swift test` green, and the gated CLI smoke test still resolves and loads its model (this is the check a dropped MLX product would break)