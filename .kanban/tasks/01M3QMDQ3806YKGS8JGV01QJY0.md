---
depends_on:
- 01M3QMDMN7RY93Y3Y3FVG37780
position_column: todo
position_ordinal: '8180'
title: Replace PooledTextEmbedding with PooledEmbedder
---
**Wait for:** FoundationModelsMetadataRegistry task 01M3QMDGR3PSYQ5PMM41Y9GJ7B ("Take PooledEmbedder directly; delete PooledTextEmbedding…") on the registry board: done and pushed.

## What
The registry deletes `PooledTextEmbedding`; `PooledEmbedder` (Extras) is a `TextEmbedding` through the Ranker.

- `Sources/MultitoolCLI/RouterDiscoverySeams.swift`: `init(librarian:embedder:sampleGenerator:)` takes `PooledEmbedder`; `acquireEmbedder(for:loader:from:)` returns `PooledEmbedder(ref: embedding.chosen, pool:)` (or is deleted if callers can make the embedder by name).
- `IntegrationTests/.../LiveRouterFixture.swift`: the same change.
- `swift package update`, confirm the new registry revision; push to `origin main` when green.

- **Added after registry 0b55573:** `MetadataSearcher` now has ONE initializer with `items:` and `embedder:`, and it is synchronous (the first search embeds the catalog). Remove `await` from each `await MetadataSearcher(` call (for example `IntegrationTests/.../NoDescriptionSurfaceDiscoveryTests.swift`); an unneeded `await` is a warning.

## Acceptance Criteria
- [ ] No Multitool source or test has `await MetadataSearcher(`.
- [ ] No Multitool source or test names `PooledTextEmbedding`.
- [ ] The Router embedding slot and the discovery embedder share one resident model.
- [ ] CI is green on the pushed commit.

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/RouterDiscoverySeamsTests.swift`: the seams take a `PooledEmbedder`; one resident model with `ModelPool(loader:)` and a test loader.
- [ ] `swift test` and `swift test --package-path IntegrationTests` pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #model-pool