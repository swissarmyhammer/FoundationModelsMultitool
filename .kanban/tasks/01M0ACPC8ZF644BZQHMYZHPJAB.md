---
assignees:
- claude-code
position_column: todo
position_ordinal: '8280'
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

- [ ] No comment in `Package.swift` names a symbol that does not exist
- [ ] The `MLXFoundationModels` dependency is kept with a true reason, or dropped
- [ ] Ungated `swift test` green, and the gated CLI smoke test still resolves and loads its model (this is the check a dropped MLX product would break)