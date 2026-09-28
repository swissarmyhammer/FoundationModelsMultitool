---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3mhyp1w3q0pznh1w5wnzr4q
  text: |-
    Research, iteration 1:
    - The resolved Router (in `.build/checkouts`) already resolves each profile into the Extras `ModelPool` (default `ModelPool.shared`). `LiveModelLoader` conforms to `PooledModelLoader`. The Router embedding container is a `PooledEmbedding`.
    - Thus, after the Router resolves `CLIRunner.demoProfile`, the embedding key is resident in `ModelPool.shared`. `PooledTextEmbedding.acquire(profile.embedding.chosen, ...)` adds a hold and does not call the loader. No new Router-only loader is necessary. The Router wiring stays in `MultitoolCLI`.
    - Design: `RouterDiscoverySeams.acquireEmbedder(for: RoutedEmbedder, loader:, from: ModelPool = .shared)` acquires by `embedding.chosen` (the `ModelRef`). `RouterDiscoverySeams.init` now takes a `PooledTextEmbedding`. `RoutedTextEmbedding` is removed (no other user). `CLIRunner.runAnswers` passes the `LiveModelLoader` of its Router. `LiveRouterFixture` acquires the embedder after the resolve and keeps it.
    - Test fixture: `makeStubProfile` gets `embeddingModel:` and `pool:` parameters, so a test can name `CLIRunner.embeddingModel` in a private pool and put no stub container into `ModelPool.shared` under a real key.
  timestamp: 2026-09-28T17:45:40.668454+00:00
- actor: claude-code
  id: 01m3mj99w1nfhwq5c4bjbseqnh
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — Sources/MultitoolCLI/RouterDiscoverySeams.swift (new `acquireEmbedder(for:loader:from:)`, init takes `PooledTextEmbedding`), Sources/MultitoolCLI/CLIRunner.swift (acquires from `ModelPool.shared` with the Router `LiveModelLoader`), Sources/MultitoolCLI/RoutedTextEmbedding.swift (deleted), IntegrationTests/.../Support/LiveRouterFixture.swift (keeps the pooled embedder), Tests/.../Fixtures/StubRouterFixtures.swift (`embeddingModel:` and `pool:` parameters), Tests/.../RouterDiscoverySeamsTests.swift (2 new pool tests).
    - test: green — `swift build --build-tests && swift test`: 1822 tests in 146 suites passed, 0 failed, 0 skipped. `swift build --package-path IntegrationTests --build-tests`: build complete. The only warnings are SwiftPM manifest-cache disk I/O and the mlx bundle "missing creator" message, which come from the tool environment and not from the code. The live-model suite did not run: the fixture change compiles, and the unit tests cover the same acquire path on a resident key.
    - commit: changed — 373cc14 feat(cli): give searchTools a pooled embedder from the model pool
    - review: clean — `review sha HEAD~1..HEAD`: 0 findings, 0 confirmed, 0 refuted. The tool rules could not read the deleted RoutedTextEmbedding.swift, which is correct for a deleted file.
    - task moved to done. The `upstream-blocked` tag is removed.
  timestamp: 2026-09-28T17:51:28.641303+00:00
depends_on:
- 01M3FMSTTSP16K9AE7JKZAEFGZ
position_column: done
position_ordinal: fff780
title: Give searchTools a pooled embedder from the registry, so that one embedding model is in memory
---
## What
Now the CLI makes a `RoutedEmbedder` from the profile's `embedding` slot and adapts it to `TextEmbedding` for `searchTools`. The router session plans a process-wide `ModelPool` in FoundationModelsExtras. With it, the registry gives `PooledTextEmbedding` and a `MetadataSearcher` initializer that takes a `ModelRef`. Then Router, the registry and Multitool share one embedding model in memory.

**Upstream blocker (other board). Do not start this task until it is done and pushed:** registry 01M3FNC0TX22X4Q7D5A5KEBHZ9 (`PooledTextEmbedding` and the `ModelRef` initializer). Registry 01M3FNBKG7PTTAGCQNN3CRNN69 (the Extras dependency) and Extras 01M3FN9BTXNPBWE6VVBQEXK4W2 (`PooledEmbedding`, `PooledEmbedder`) come before it.

- [x] In `Sources/MultitoolCLI/` (`CLIRunner.swift` and the discovery-seams adapter file), give `searchTools` a `PooledTextEmbedding` for `CLIRunner.embeddingModel` in place of the Router embedder adapter.
- [x] Remove the Router embedder adapter (`RoutedTextEmbedding`) if nothing else uses it.
- [x] Update the IntegrationTests call sites that build an embedder from `fixture.profile.embedding`.

## Acceptance Criteria
- [x] The CLI gets the embedder for `searchTools` from the pool by `ModelRef`.
- [x] A test proves that a second request for the same embedding `ModelRef` in the same process loads no second model.
- [x] `swift test` passes.

## Tests
- [x] A unit test in `Tests/FoundationModelsMultitoolTests/` over the CLI seams: two requests for `CLIRunner.embeddingModel` give the same pooled instance (use the pool's own test seam, if it has one).
- [x] Run `swift build --build-tests && swift test`. Expected result: all tests pass.

## Workflow
- Use `/tdd`. Write failing tests first, then do the implementation that makes them pass.