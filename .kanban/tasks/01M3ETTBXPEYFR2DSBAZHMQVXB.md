---
assignees:
- claude-code
depends_on:
- 01M3EVK4VR545ABV6R9YHFQH76
position_column: todo
position_ordinal: '8280'
title: Give demoProfile a flash model that is not the standard model, and report a same-model searchTools call clearly
---
## What
With the work-queue Router, a synchronous (in-band) tool body that calls a session on the same model as the open submission is refused at once with `GenerationQueueError.waitInsideOpenSubmission(model:)`. See `../FoundationModelsRouter/Sources/FoundationModelsRouter/Session/RoutedSession.swift:36-45` and `RoutedSessionActorGeneration.swift:99-102`. `searchTools` is synchronous. It runs the selection tier on the librarian (`profile.flash`, `Sources/FoundationModelsMultitool/Discovery/SearchToolsTool.swift:360-390`) and the optional sample generator (`makeSample`, `:395`). `CLIRunner.demoProfile` (`Sources/MultitoolCLI/CLIRunner.swift:421-450`) puts `generationModel` in both `standard` and `flash`, so each librarian call is refused.

User decision (2026-09-26): keep `searchTools` synchronous and require a flash model that is different from the standard model.

- [ ] `Sources/MultitoolCLI/CLIRunner.swift`: add `public static let flashModel: ModelRef = "mlx-community/Qwen3-4B-4bit"`, because the integration suite already grades the selection tier on this model. Set `demoProfile.flash = [flashModel]`. Rewrite the comments at `CLIRunner.swift:386-450` and `:844-848` that say one model serves both slots. In `IntegrationTests/.../Support/LiveRouterFixture.swift:430`, set `agentFlashModel = CLIRunner.flashModel`, so the literal is in one place only.
- [ ] Do not let the refusal fail silently. Find where the selection tier and `SampleSnippet` (`Discovery/SampleSnippet.swift:128` uses `try?`) handle a session error. Selection runs through `RoutedAgentSession.respond` (`Discovery/RoutedAgentSession.swift:34`) into `SelectionTier` in FoundationModelsMetadataRegistry. Make `searchTools` return a tool error for `waitInsideOpenSubmission`. The error text must say that the librarian model must be different from the model of the calling session. If only a FoundationModelsMetadataRegistry change can surface it, stop, and write the card text for that repo's board (see memory `cross-repo-cards-go-on-their-board`).
- [ ] Document the rule on `MultiTool.Builder.makeSessionTools(librarian:embedder:sampleGenerator:)` and `makeSessionToolsAndStaging` (`Sources/FoundationModelsMultitool/MultiTool.swift:161-200`), and in README.md where it describes the librarian.

## Acceptance Criteria
- [ ] `CLIRunner.demoProfile.flash` and `CLIRunner.demoProfile.standard` have no model in common.
- [ ] A `searchTools` call whose librarian session throws `GenerationQueueError.waitInsideOpenSubmission` gives a tool error that names the fix. It does not give an empty or signature-only selection.
- [ ] The same holds for the sample generator: the refusal gives a visible note or error, not a silent `nil`.
- [ ] `demoProfile` still resolves with both models loaded and with the new context default (the model's own window): `CLISmokeTests` passes with a real model.

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/SearchToolsToolTests.swift`: a stub `AgentSession` librarian (see `Fixtures/AgentSessionFixtures.swift`) that throws `GenerationQueueError.waitInsideOpenSubmission(model:)` gives the tool error.
- [ ] `Tests/FoundationModelsMultitoolTests/SampleSnippetTests.swift`: the same refusal from the generator is reported.
- [ ] A unit test asserts that `demoProfile`'s `flash` and `standard` model lists do not overlap.
- [ ] Run `swift test`. Expected result: all tests pass. Then run `swift test --package-path IntegrationTests --no-parallel --filter CLISmokeTests`. Expected result: it passes.

## Workflow
- Use `/tdd`. Write failing tests first, then do the implementation that makes them pass.