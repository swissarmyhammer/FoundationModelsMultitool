---
comments:
- actor: claude-code
  id: 01m3tfkhyptv1myj3z2vbrkjta
  text: |-
    Research at HEAD e3d91b4. Items that commit d7973b7 (^vg37780) already satisfies:
    - "No Multitool source or test has `await MetadataSearcher(`": satisfied. `rg "await MetadataSearcher\(" Sources Tests IntegrationTests/Tests` finds no match.
    - "No Multitool source or test names `PooledTextEmbedding`": satisfied. `rg PooledTextEmbedding` finds no match.
    - "`init(librarian:embedder:sampleGenerator:)` takes `PooledEmbedder`": satisfied. Sources/MultitoolCLI/RouterDiscoverySeams.swift declares `public init(librarian: RoutedLLM, embedder: PooledEmbedder, sampleGenerator: RoutedLLM? = nil)`.
    - LiveRouterFixture.swift keeps `private let embedder: PooledEmbedder` and makes the seams with it.
    - `swift package update`: not necessary. The resolved registry revision 8399118f is registry origin/main, and it has no `PooledTextEmbedding`.

    Open items:
    - `acquireEmbedder` returns `PooledEmbedder(hold:)` after `pool.acquire(key, footprintBytes:, sessionBytes: 0, loader:)`. The card asks for `PooledEmbedder(ref: embedding.chosen, pool:)`.
    - RouterDiscoverySeamsTests has no test with `ModelPool(loader:)` and a test loader.

    Facts from Extras (.build/checkouts/FoundationModelsExtras, ModelPool/PooledEmbedder.swift and ModelPool.swift):
    - `PooledEmbedder(ref:pool:)` loads nothing when you make it. Its first `embed(texts:)` calls `pool.acquire(key)`. A resident key adds a hold and loads nothing. A new key loads with `pool.loader`, the loader of `ModelPool(loader:)`. The default of `ModelPool.shared` is `MLXModelLoader`.
    - Thus the `loader:` parameter of `acquireEmbedder` becomes dead, and the function need not be async or throwing.
    - The Router resolves each profile into `ModelPool.shared` when it gets no pool (CLIRunner and LiveRouterFixture). The profile keeps the Router hold, so the first embed adds a hold to the resident model. One resident model stays true.

    Plan: `acquireEmbedder(for:from:)` returns `PooledEmbedder(ref: embedding.chosen, pool: pool)`. Remove `loader:`, `async` and `throws`. Update the callers in CLIRunner.swift and LiveRouterFixture.swift. Write the tests first with `ModelPool(loader:)` and a counting test loader.
  timestamp: 2026-10-01T01:00:05.462440+00:00
- actor: claude-code
  id: 01m3thq42tb69r0j5tgacdag35
  text: |-
    Implementation landed (not committed).

    - Sources/MultitoolCLI/RouterDiscoverySeams.swift: `acquireEmbedder(for:from:)` now returns `PooledEmbedder(ref: embedding.chosen, pool: pool)`. Extras offers both `init(ref:pool:)` and `init(hold:)`; the card asks for `ref:pool:`. The `loader:` parameter, `async`, `throws` and the private `embeddingSessionBytes` constant are gone. The pool loads with its own loader (`ModelPool(loader:)`). The embedder loads nothing when you make it. Its first embed call acquires the model. While the Router profile exists, the Router keeps a hold of the embedding model, so the pool only adds a hold. That keeps one resident model.
    - Sources/MultitoolCLI/CLIRunner.swift and IntegrationTests/.../Support/LiveRouterFixture.swift: the callers use `RouterDiscoverySeams.acquireEmbedder(for: profile.embedding)`. The comments now tell about the lazy hold.
    - Tests/FoundationModelsMultitoolTests/Fixtures/StubRouterFixtures.swift: the doc reference now names `acquireEmbedder(for:from:)`.
    - Tests/FoundationModelsMultitoolTests/RouterDiscoverySeamsTests.swift (TDD, RED was a compile failure "missing argument for parameter 'loader'"): new tests with `ModelPool(loader: CountingEmbeddingLoader())`. "the embedder loads nothing when it is made". "two embedders of the CLI embedding model in one pool load the model one time, through the loader of the pool". "the Router embedding slot and the discovery embedder share one resident model": the Router resolves into the same pool, the first embed loads nothing (`loads == 0`), the resident count does not change, and the vectors are equal to the vectors of the Router embedding handle.
    - `swift package update` was not run. The resolved registry 8399118f is registry origin/main.

    Test runs (each one time):
    - `swift test --filter RouterDiscoverySeamsTests`: 14 of 14 pass.
    - `swift test`: 1877 tests in 154 suites pass, 0 warnings.
    - `swift test --package-path IntegrationTests --no-parallel`: 57 of 60 pass. The 3 failures came from the network: BraveHTMLLiveTests "a site search for developer.apple.com gives only hits under apple.com" (`braveHTML: blocked (HTTP 429)`), and OverBudgetSurfaceDiscoveryTests and RetrievalTextSurfaceDiscoveryTests (`metadata unavailable (The request timed out.)` inside `Router.resolve`, before the fixture makes the embedder). New card ^kghyac5 records them. The Tests checkbox for the integration run stays unchecked.
  timestamp: 2026-10-01T01:36:59.482013+00:00
- actor: claude-code
  id: 01m3thq99fxywh9ab9ybp422t4
  text: |-
    ### implement — changed
    - evidence: 5 files — Sources/MultitoolCLI/RouterDiscoverySeams.swift, Sources/MultitoolCLI/CLIRunner.swift, IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Support/LiveRouterFixture.swift, Tests/FoundationModelsMultitoolTests/RouterDiscoverySeamsTests.swift, Tests/FoundationModelsMultitoolTests/Fixtures/StubRouterFixtures.swift. `swift test`: 1877 tests in 154 suites pass. `swift test --package-path IntegrationTests --no-parallel`: 57 of 60 pass, 3 failures from the network (HTTP 429, metadata request timeout), recorded on ^kghyac5.
    - next: /review. Push is a user step; "CI is green on the pushed commit" stays unchecked.
  timestamp: 2026-10-01T01:37:04.815421+00:00
- actor: claude-code
  id: 01m3tk0xp2sh2rej0718cfnng5
  text: |-
    ### test - stuck
    - load average at start: 33.63 46.17 57.42 (uptime).
    - root: `swift test` - 1877 tests, 154 suites, 0 failed, 0 issues, 0 skipped, passed in 13.064 s. The only warning is a build-tool line: "missing creator for mutated node ... mlx-swift_Cmlx.bundle/Contents/MacOS". It is not from project code.
    - integration: `swift test --package-path IntegrationTests --no-parallel` - 60 tests, 32 suites, 0 failed, 0 issues, 6 skipped, passed in 1232.615 s. Same build-tool warning.
    - The 3 earlier failures (Brave HTTP 429 and two Hugging Face Hub "metadata unavailable (The request timed out.)" in Router.resolve) did NOT occur in this run. They were network failures: the failure text is an HTTP status and a URLSession timeout. Both come from a remote call, so the code change cannot reach them. This run did not hit them again, and card ^kghyac5 still tracks them.
    - No root wall-clock race (card ^0hd2aq3 suites) failed.
    - The 6 skipped tests are the live search provider tests: braveAPI (BRAVE_SEARCH_API_KEY or BRAVE_API_KEY), tavily (TAVILY_API_KEY), exa (EXA_API_KEY), serper (SERPER_API_KEY), kagi (KAGI_API_KEY), searxng (SEARXNG_URL). Each skips because a credential is not set. They are not in the code of this task.
    - The test skill says zero skipped. I cannot fix a missing credential, and I did not edit or skip tests. A person must decide on this policy.
    - No source or test file was changed in this step. No commit, no push.
    - next: a person decides on the 6 credential-gated skips. All other results are green.
  timestamp: 2026-10-01T01:59:49.186083+00:00
- actor: claude-code
  id: 01m3tk1tn0rmakgygeb05y8t9r
  text: |-
    ### commit — changed
    - evidence: 373cfea refactor(discovery): replace PooledTextEmbedding with PooledEmbedder in acquireEmbedder; base e3d91b4
    - next: review
  timestamp: 2026-10-01T02:00:18.848227+00:00
depends_on:
- 01M3QMDMN7RY93Y3Y3FVG37780
position_column: doing
position_ordinal: '80'
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
- [x] No Multitool source or test has `await MetadataSearcher(`.
- [x] No Multitool source or test names `PooledTextEmbedding`.
- [x] The Router embedding slot and the discovery embedder share one resident model.
- [ ] CI is green on the pushed commit.

## Tests
- [x] `Tests/FoundationModelsMultitoolTests/RouterDiscoverySeamsTests.swift`: the seams take a `PooledEmbedder`; one resident model with `ModelPool(loader:)` and a test loader.
- [ ] `swift test` and `swift test --package-path IntegrationTests` pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #model-pool