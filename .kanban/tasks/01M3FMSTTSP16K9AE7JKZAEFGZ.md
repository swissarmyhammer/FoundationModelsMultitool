---
assignees:
- claude-code
depends_on:
- 01M3EVKKTGVDQAKH1X7HD44HRE
position_column: todo
position_ordinal: 8c80
title: Take the metadata-registry seams in the discovery API, and move the Router adapters to the CLI host
---
## What
User decision (2026-09-26): tool discovery must not depend on Router model types. It uses the seams of FoundationModelsMetadataRegistry, which re-exports them from FoundationModelsRanker: `SelectionConfig` / `SelectionSessionSource` (`.factory(@Sendable (String) -> any AgentSession)` or `.session(any AgentSession)`), `any TextEmbedding`, and `AgentSession`. The host picks the models and adapts them.

Current Router coupling in discovery:
- `MultiTool.Builder.makeSessionTools(librarian: RoutedLLM?, embedder: RoutedEmbedder?, sampleGenerator: RoutedLLM?)` and `makeSessionToolsAndStaging(...)` (`Sources/FoundationModelsMultitool/MultiTool.swift:161-230`).
- `SearchToolsTool.init(registry:librarian:embedder:sampleGenerator:)`, `makeSelection(librarian:ids:)`, `makeEmbedding(from:)`, `makeSample(generator:)` (`Sources/FoundationModelsMultitool/Discovery/SearchToolsTool.swift:190-410`).
- The adapters `Discovery/RoutedAgentSession.swift`, `Discovery/RoutedTextEmbedding.swift` and `Discovery/SelectionGrammar.swift` (a Router `Grammar` from the id set). `Capabilities/MCP/SurfaceRefresher.swift` also calls the builder.

Change:
- [ ] Change the builder methods and `SearchToolsTool.init` to take registry seams. For example: `selection: SelectionConfig?`, `embedder: (any TextEmbedding)?`, `sampleSession: (@Sendable (String) -> any AgentSession)?`. The selection tier needs the id set to build its grammar (`SelectionTier.idEnumSchema(ids:)`), and the host cannot know it in advance. If so, take a factory keyed by the ids (for example `@Sendable ([String]) throws -> SelectionConfig?`) and write the reason in its doc comment. Keep the `TracedAgentSession` tracing around each session in the library.
- [ ] Move `RoutedAgentSession`, `RoutedTextEmbedding` and `SelectionGrammar` out of `Sources/FoundationModelsMultitool/Discovery/` into `Sources/MultitoolCLI/` (for example `RouterDiscoverySeams.swift`). Make them `public` there, because `IntegrationTests` reaches `MultitoolCLI` as a product. Give one entry point that turns a `RoutedLLM` librarian, a `RoutedEmbedder` and an optional `RoutedLLM` generator into the seams. `CLIRunner` uses it.
- [ ] Move their tests with them (`SelectionGrammarTests.swift`, `DiscoveryEmbedderTests.swift`, and the `RoutedAgentSession` cases). Change the other unit-test call sites to the new signatures (`SearchToolsToolTests`, `MultiToolExecutionTests`, `SiblingToolPathTests`, `RegistrySwapTests`, `RouterSessionMountTests`, `ExamplesTests`, `FilesCapabilityTests`, `MCPCapabilityTests`, `ShellCapabilityTests`, `OverBudgetSelectionOrderTests`, `SurfaceRefresherTests`, `Support/CapabilityDiscoveryProbe.swift`). Most pass `nil`.
- [ ] Update README.md, where it shows `makeSessionTools(librarian:...)`, and `ExamplesTests`, which checks the README examples.
- [ ] Do not change `IntegrationTests/`. Task 01M3ETV0A0AE2F2MTGWTFHF7T4 changes its call sites.

Do not change `SearchToolsTool.mount` (a Router `ToolMount`). That is how a tool mounts on a session, not a model dependency.

## Acceptance Criteria
- [ ] `rg -n 'RoutedLLM|RoutedEmbedder|RoutedSession|Grammar\b' Sources/FoundationModelsMultitool/Discovery Sources/FoundationModelsMultitool/MultiTool.swift` returns no match (doc comments included).
- [ ] The public discovery API names only registry, Ranker or Multitool types.
- [ ] `multitool-cli` still gets selection, embedding and samples through the adapters in `MultitoolCLI`.
- [ ] `swift build --build-tests` and `swift test` pass.

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/SearchToolsToolTests.swift`: a `SelectionConfig` over a stub `AgentSession` (no Router) drives selection end to end.
- [ ] `Tests/FoundationModelsMultitoolTests/RouterDiscoverySeamsTests.swift` (new, or the moved suites): the CLI adapter builds a selection config whose sessions carry the id grammar, and an embedding with the embedder's dimension.
- [ ] Run `swift build --build-tests && swift test`. Expected result: all tests pass.

## Workflow
- Use `/tdd`. Write failing tests first, then do the implementation that makes them pass.