---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3mhhhrw28s7hsqeynfb89az
  text: |-
    ### Research — registry at 32288c5 has no API to share vectors

    What I found in `../FoundationModelsMetadataRegistry` (commit 32288c5):

    - `MetadataIndex` is a value type (`struct`). Each `Entry` keeps its own `embedding: [Float]?`. The only public way to fill the vectors is `MetadataIndex.build(items:embedder:previous:onDiagnostic:)`, and it is `async`. `mergingEmbeddings(...)`, `pendingEmbeddings()` and `incrementalBaseline(...)` are `internal`.
    - `MetadataSearcher` is an `actor`. The synchronous `init(index:mode:weights:embedder:selection:onDiagnostic:)` keeps its own copy of the index. Its first `search(intent:limit:)` runs `FirstSearchCatchUp`, which embeds all pending entries of THAT searcher only, and merges them into THAT actor's `index`. Two searchers made from the same unembedded index thus embed the catalog two times. There is no public init or method that lets two searchers share one catch-up, one vector store, or one index.
    - `PooledTextEmbedding` forwards each `embed(_:)` call to the pooled model queue. It keeps no cache of vectors.
    - In this repo, `RegistryBundle.init(registry:shape:)` must stay synchronous: `RegistryHolder.applyStaged()` (`Sources/FoundationModelsMultitool/RegistryHolder.swift:77`) and the `MultiTool` initializers (`MultiTool.swift:212`, `:218`, `:446`) call it synchronously. Thus the bundle cannot `await MetadataIndex.build(...)` one time and give the embedded index to both searchers. Also, that change would move the catalog embed from the first search to the bundle build, and the tests in `DiscoveryEmbedderTests` record the lazy embed at the first search.

    Result: the registry has no API for this task. As the card tells, I stop here. The card text for the registry board is in the next comment.
  timestamp: 2026-09-28T17:38:30.300314+00:00
- actor: claude-code
  id: 01m3mhhzb43n8r0sd56650c1pm
  text: |-
    ### Card text for the FoundationModelsMetadataRegistry board

    Send this card to the peer session of FoundationModelsMetadataRegistry. Do not add it to the FoundationModelsMultitool board.

    ---
    **Title:** Let two synchronously built `MetadataSearcher`s share one catalog embed

    ## What
    A consumer (FoundationModelsMultitool `RegistryBundle`) builds two `MetadataSearcher<Item>` over the same items and the same embedder, with different `Weights` and `SearchMode`. It must build them synchronously, so it uses `init(index:mode:weights:embedder:selection:onDiagnostic:)` over an unembedded `MetadataIndex`. Each searcher then runs its own `FirstSearchCatchUp` and embeds the whole catalog. The catalog is embedded two times for each bundle, and again after each registry swap.

    Add a public, synchronous API that lets two or more searchers share one first-search embed of one index. One possible shape (the implementer can choose a different shape with the same effect):

    - A public reference type, for example `public final class SharedCatalogEmbedding<Item>: Sendable` (or an `actor`), made synchronously from a `MetadataIndex<Item>` and an embedder. It runs the catch-up one time (single flight), and gives the embedded vectors to each searcher that uses it.
    - A new synchronous `MetadataSearcher.init(sharing: SharedCatalogEmbedding<Item>, mode:weights:selection:onDiagnostic:)`. At its first search, the searcher awaits the shared catch-up and merges the shared vectors into its own `index` (through the existing hash-checked `mergingEmbeddings`), in place of a catch-up of its own.

    Keep these behaviors the same as now: the catalog embed occurs at the first search of any sharing searcher, not at init; a failed embed leaves each sharing searcher keyword-only and marks the catch-up done; `update(items:)` on one searcher does not change the other searchers.

    ## Acceptance Criteria
    - [ ] Two searchers made synchronously through the new API over one index call the embedder over the catalog one time in total, at the first search of either searcher.
    - [ ] Two concurrent first searches (one on each searcher) cause one catalog embed call, not two.
    - [ ] The rankings of each searcher are the same as the rankings of a searcher made with `init(index:...)` with the same weights and mode.
    - [ ] A catalog embed that fails leaves both searchers answering keyword-only, with no second catalog embed for the life of the shared value.

    ## Tests
    - [ ] A counting stub `TextEmbedding` records each batch. Two sharing searchers, one search each: exactly one catalog batch plus one query batch per search.
    - [ ] The concurrency case with `async let` on the two searchers: one catalog batch.
    - [ ] Ranking parity with the per-searcher catch-up for three fixed queries and two different `Weights`.
    - [ ] The failing-embedder case.
    - [ ] Run `swift test`. Expected result: all tests pass.

    ## Consumer
    FoundationModelsMultitool task ^57bedj6 waits on this card. After it lands, that task changes `RegistryBundle.init(registry:shape:)` to build one shared embedding and give it to `hintSearcher` and `discoverySearcher`.
    ---
  timestamp: 2026-09-28T17:38:44.196264+00:00
- actor: claude-code
  id: 01m3mhj5p5tm8zesby05149xx5
  text: |-
    ### implement — stuck
    - evidence: no files changed. The registry at 32288c5 has no public synchronous API that lets two `MetadataSearcher`s share one catalog embed, and `RegistryBundle.init` must stay synchronous (`RegistryHolder.applyStaged()`, `MultiTool` initializers). `PooledTextEmbedding` keeps no vector cache.
    - next: a person sends the card text in the comment above to the FoundationModelsMetadataRegistry board. After that card lands and this package resolves the new registry, start this task again.

    ### finish iteration 1 — stuck
    - implement: stuck — registry has no shared-vector API (card text for the registry board in a comment above)
    - test: not run (no change)
    - commit: not run (no change)
    - review: not run
  timestamp: 2026-09-28T17:38:50.693414+00:00
- actor: claude-code
  id: 01m3mhm0yz59drh0chvf59vfv4
  text: 'Blocker is on the FoundationModelsMetadataRegistry board: 01M3MHKS0YD6GQT1KKAMHCHPNY, "Let two synchronously built MetadataSearchers share one catalog embed" (2026-09-28, added by the router session). It is in To Do and not committed in the registry repo yet. Start this task again when that card is done and pushed, and this package resolves the new registry.'
  timestamp: 2026-09-28T17:39:51.391279+00:00
depends_on:
- 01M3FMSTTSP16K9AE7JKZAEFGZ
position_column: doing
position_ordinal: '80'
title: Embed the catalog one time for each RegistryBundle, and share the vectors between the hint and discovery searchers
---
## What
`Sources/FoundationModelsMultitool/RegistryBundle.swift:152-160` builds two `MetadataSearcher<APISurface.Entry>` instances, `hintSearcher` and `discoverySearcher` (through `SearchToolsTool.makeSearcher`), over the same entries with the same embedder. So each bundle embeds the whole catalog two times, and it does this again after each registry swap (`RegistryHolder.applyStaged()`). This task has no upstream blocker.

- [ ] Find out how `MetadataSearcher` / `MetadataIndex` (`../FoundationModelsMetadataRegistry/Sources/FoundationModelsMetadataRegistry/`) keep their vectors, and whether two searchers can share one index or one set of vectors. The two searchers use different fusion weights (`RegistryBundle.swift:20`).
- [ ] Embed the entries one time for each bundle, and give the vectors to both searchers. If the registry has no API for this, stop, and write the card text for the registry board (see memory `cross-repo-cards-go-on-their-board`).
- [ ] Keep the ranking results of both searchers the same as before.

## Acceptance Criteria
- [ ] Building one `RegistryBundle` with an embedder calls the embedder over the catalog one time, not two times.
- [ ] The hint and discovery results for a fixed query set are the same as before the change.

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/` (new or existing registry-bundle suite): a counting stub `TextEmbedding` records the texts it embeds. Building a bundle over N entries embeds each entry text one time.
- [ ] The same suite: the hint and discovery rankings for three fixed queries are the same as a recorded baseline.
- [ ] Run `swift test`. Expected result: all tests pass.

## Workflow
- Use `/tdd`. Write failing tests first, then do the implementation that makes them pass. #upstream-blocked