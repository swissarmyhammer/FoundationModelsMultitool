---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3fmt8dhm0d8zpby9y2tzn3x
  text: |-
    Scope change (2026-09-26), from user decision: discovery takes metadata-registry seams (task 01M3FMSTTSP16K9AE7JKZAEFGZ, which this task now depends on). Thus:
    - The discovery library (`Sources/FoundationModelsMultitool/Discovery/`) must not name `GenerationQueueError`. Make discovery show ANY error of the librarian session and of the sample session as a visible tool error or note, not as a silent empty selection or a silent `nil` (`SampleSnippet.swift` `try?`). Test this with a stub `AgentSession` that throws.
    - The Router-specific text is in the CLI adapter in `Sources/MultitoolCLI/` (the moved `RoutedAgentSession`). It maps `GenerationQueueError.waitInsideOpenSubmission` to an error whose text says that the librarian model must be different from the model of the calling session. Test this in the adapter's own suite.
    - The `demoProfile` flash model change (`CLIRunner.flashModel`, `agentFlashModel = CLIRunner.flashModel`, the no-overlap unit test) stays as written.
    - Also correct the comments that still name `turnLock` / `generationGate` about the same-model deadlock: `Sources/FoundationModelsMultitool/Discovery/SearchToolsTool.swift:336-356` (or where they are after the move) and `Sources/MultitoolCLI/CLIRunner.swift:464`. Task ^b1a2yqb recorded these.
  timestamp: 2026-09-26T19:59:29.201172+00:00
- actor: claude-code
  id: 01m3fpfb31cm5b96bfq5km4jkc
  text: |-
    Scope addition (2026-09-26), from the router session (user decisions):
    - `standard` and `flash` must never be the same model. Router task 01M3FP4SPYCEJ1Y6PRYZSRRNAT makes `Router.resolve` refuse a profile where they are the same. This task does not wait for it: the `demoProfile` change is correct with or without it.
    - `searchTools` stays synchronous. It waits until the registry work is done. A synchronous selection call on `flash`, inside an open submission on `standard`, waits on the FIFO queue of `flash`. The queue throws `waitInsideOpenSubmission` only when the model is the same.
    - Remove the "known deadlock" note of `demoProfile` in `Sources/MultitoolCLI/CLIRunner.swift` (about lines 489-514 on 2026-09-26).
    - Document in the seams file `Sources/FoundationModelsMultitool/Discovery/SearchToolsTool+Seams.swift` that the selection model must not be the model of the calling session.
  timestamp: 2026-09-26T20:28:28.641540+00:00
- actor: claude-code
  id: 01m3fq1adexe3493b59rq8nx96
  text: |-
    Implementation notes (iteration 1):
    - FoundationModelsMetadataRegistry/Ranker does NOT swallow the librarian error: `MetadataSearcher.search` (.auto) and `SelectionTier.search` rethrow the session error unchanged. Thus no cross-repo card is necessary. The selection error already reached the model as the error of the `searchTools` call; the new tests hold that.
    - The sample path swallowed the error (`try?` in `SampleSnippet.generate`). Now `generate` throws, and `SearchToolsTool` shows a note (`SampleOutcome.failed(note:)`, lead `sampleFailureLead`) beside the signatures.
    - The library `Discovery/` does not name `GenerationQueueError`. The CLI adapter `RoutedAgentSession.explained(_:)` maps `waitInsideOpenSubmission` to the new `SameModelDiscoveryError`, whose text says "The librarian model must be different from the model of the calling session. Use a flash model that is different from the standard model." Router shows a failed tool call as `String(describing:)`, so the error is `CustomStringConvertible`.
    - `CLIRunner.flashModel = "mlx-community/Qwen3-4B-4bit"`, `demoProfile.flash = [flashModel]`. The "known deadlock" note is removed. The stale `turnLock`/`generationGate` text in `RouterDiscoverySeams.makeSelection` (the moved location of the SearchToolsTool.swift:336-356 comment) and the CLIRunner comments are rewritten for the per-model FIFO queue.
    - `IntegrationTests/.../Support/LiveRouterFixture.swift`: `agentFlashModel = CLIRunner.flashModel` (one-line change, done).
    - Live check (`swift test --package-path IntegrationTests --no-parallel --filter CLISmokeTests`) is not run here: the IntegrationTests package does not compile yet (task 01M3ETV0A0AE2F2MTGWTFHF7T4 owns that). The live check moves to task 01M3ETVQGBG0R25ED1ER77ER9Z (comment added there).
    - `swift test` prints `warning: missing creator for mutated node: (.../mlx-swift_Cmlx.bundle/Contents/MacOS)`. This is a SwiftPM build-system message about the resource bundle of the mlx-swift dependency, not a compiler warning of this package; it is present without this change.
  timestamp: 2026-09-26T20:38:17.774863+00:00
- actor: claude-code
  id: 01m3fqcx1njpqngs7dxx0ybxgg
  text: |-
    ### finish iteration 1 — clean
    - implement — changed: 13 files (Discovery/SampleSnippet.swift, Discovery/SearchToolsTool.swift, Discovery/SearchToolsTool+Seams.swift, MultiTool.swift, MultitoolCLI/CLIRunner.swift, MultitoolCLI/RoutedAgentSession.swift, MultitoolCLI/RouterDiscoverySeams.swift, README.md, IntegrationTests/.../LiveRouterFixture.swift, tests: SearchToolsToolTests, SampleSnippetTests, RouterDiscoverySeamsTests, new DemoProfileTests)
    - test — green: `swift build --build-tests && swift test` — 1808 tests in 145 suites passed, 0 failed, 0 skipped (the one SwiftPM message `missing creator for mutated node` is about the mlx-swift resource bundle, not this package)
    - commit — changed: 3c3de1d fix(discovery): give demoProfile a different flash model, and show a same-model searchTools error
    - review — clean: `review sha HEAD~1..HEAD` — 0 findings, 0 confirmed, 0 refuted (14 attempted)
    - open: the live CLISmokeTests check moved to task 01M3ETVQGBG0R25ED1ER77ER9Z (IntegrationTests does not compile until 01M3ETV0A0AE2F2MTGWTFHF7T4 is done).
  timestamp: 2026-09-26T20:44:37.301685+00:00
depends_on:
- 01M3EVK4VR545ABV6R9YHFQH76
- 01M3FMSTTSP16K9AE7JKZAEFGZ
position_column: done
position_ordinal: fff380
title: Give demoProfile a flash model that is not the standard model, and report a same-model searchTools call clearly
---
## What
With the work-queue Router, a synchronous (in-band) tool body that calls a session on the same model as the open submission is refused at once with `GenerationQueueError.waitInsideOpenSubmission(model:)`. See `../FoundationModelsRouter/Sources/FoundationModelsRouter/Session/RoutedSession.swift:36-45` and `RoutedSessionActorGeneration.swift:99-102`. `searchTools` is synchronous. It runs the selection tier on the librarian (`profile.flash`, `Sources/FoundationModelsMultitool/Discovery/SearchToolsTool.swift:360-390`) and the optional sample generator (`makeSample`, `:395`). `CLIRunner.demoProfile` (`Sources/MultitoolCLI/CLIRunner.swift:421-450`) puts `generationModel` in both `standard` and `flash`, so each librarian call is refused.

User decision (2026-09-26): keep `searchTools` synchronous and require a flash model that is different from the standard model.

- [x] `Sources/MultitoolCLI/CLIRunner.swift`: add `public static let flashModel: ModelRef = "mlx-community/Qwen3-4B-4bit"`, because the integration suite already grades the selection tier on this model. Set `demoProfile.flash = [flashModel]`. Rewrite the comments at `CLIRunner.swift:386-450` and `:844-848` that say one model serves both slots. In `IntegrationTests/.../Support/LiveRouterFixture.swift:430`, set `agentFlashModel = CLIRunner.flashModel`, so the literal is in one place only.
- [x] Do not let the refusal fail silently. Find where the selection tier and `SampleSnippet` (`Discovery/SampleSnippet.swift:128` uses `try?`) handle a session error. Selection runs through `RoutedAgentSession.respond` (`Discovery/RoutedAgentSession.swift:34`) into `SelectionTier` in FoundationModelsMetadataRegistry. Make `searchTools` return a tool error for `waitInsideOpenSubmission`. The error text must say that the librarian model must be different from the model of the calling session. If only a FoundationModelsMetadataRegistry change can surface it, stop, and write the card text for that repo's board (see memory `cross-repo-cards-go-on-their-board`).
- [x] Document the rule on `MultiTool.Builder.makeSessionTools(librarian:embedder:sampleGenerator:)` and `makeSessionToolsAndStaging` (`Sources/FoundationModelsMultitool/MultiTool.swift:161-200`), and in README.md where it describes the librarian.

## Acceptance Criteria
- [x] `CLIRunner.demoProfile.flash` and `CLIRunner.demoProfile.standard` have no model in common.
- [x] A `searchTools` call whose librarian session throws `GenerationQueueError.waitInsideOpenSubmission` gives a tool error that names the fix. It does not give an empty or signature-only selection.
- [x] The same holds for the sample generator: the refusal gives a visible note or error, not a silent `nil`.
- [ ] `demoProfile` still resolves with both models loaded and with the new context default (the model's own window): `CLISmokeTests` passes with a real model. (Moved to task 01M3ETVQGBG0R25ED1ER77ER9Z: the IntegrationTests package does not compile until task 01M3ETV0A0AE2F2MTGWTFHF7T4 is done.)

## Tests
- [x] `Tests/FoundationModelsMultitoolTests/SearchToolsToolTests.swift`: a stub `AgentSession` librarian (see `Fixtures/AgentSessionFixtures.swift`) that throws `GenerationQueueError.waitInsideOpenSubmission(model:)` gives the tool error.
- [x] `Tests/FoundationModelsMultitoolTests/SampleSnippetTests.swift`: the same refusal from the generator is reported.
- [x] A unit test asserts that `demoProfile`'s `flash` and `standard` model lists do not overlap.
- [ ] Run `swift test`. Expected result: all tests pass. Then run `swift test --package-path IntegrationTests --no-parallel --filter CLISmokeTests`. Expected result: it passes. (`swift test`: 1808 tests pass. The live check moved to task 01M3ETVQGBG0R25ED1ER77ER9Z.)

## Workflow
- Use `/tdd`. Write failing tests first, then do the implementation that makes them pass.