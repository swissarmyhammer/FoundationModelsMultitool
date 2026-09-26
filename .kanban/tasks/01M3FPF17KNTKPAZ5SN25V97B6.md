---
assignees:
- claude-code
depends_on:
- 01M3FMSTTSP16K9AE7JKZAEFGZ
position_column: todo
position_ordinal: 8d80
title: Give searchTools a pooled embedder from the registry, so that one embedding model is in memory
---
## What
Now the CLI makes a `RoutedEmbedder` from the profile's `embedding` slot and adapts it to `TextEmbedding` for `searchTools`. The router session plans a process-wide `ModelPool` in FoundationModelsExtras. With it, the registry gives `PooledTextEmbedding` and a `MetadataSearcher` initializer that takes a `ModelRef`. Then Router, the registry and Multitool share one embedding model in memory.

**Upstream blocker (other board). Do not start this task until it is done and pushed:** registry 01M3FNC0TX22X4Q7D5A5KEBHZ9 (`PooledTextEmbedding` and the `ModelRef` initializer). Registry 01M3FNBKG7PTTAGCQNN3CRNN69 (the Extras dependency) and Extras 01M3FN9BTXNPBWE6VVBQEXK4W2 (`PooledEmbedding`, `PooledEmbedder`) come before it.

- [ ] In `Sources/MultitoolCLI/` (`CLIRunner.swift` and the discovery-seams adapter file), give `searchTools` a `PooledTextEmbedding` for `CLIRunner.embeddingModel` in place of the Router embedder adapter.
- [ ] Remove the Router embedder adapter (`RoutedTextEmbedding`) if nothing else uses it.
- [ ] Update the IntegrationTests call sites that build an embedder from `fixture.profile.embedding`.

## Acceptance Criteria
- [ ] The CLI gets the embedder for `searchTools` from the pool by `ModelRef`.
- [ ] A test proves that a second request for the same embedding `ModelRef` in the same process loads no second model.
- [ ] `swift test` passes.

## Tests
- [ ] A unit test in `Tests/FoundationModelsMultitoolTests/` over the CLI seams: two requests for `CLIRunner.embeddingModel` give the same pooled instance (use the pool's own test seam, if it has one).
- [ ] Run `swift build --build-tests && swift test`. Expected result: all tests pass.

## Workflow
- Use `/tdd`. Write failing tests first, then do the implementation that makes them pass. #upstream-blocked