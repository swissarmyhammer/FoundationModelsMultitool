---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: 'Remove the two discovery workarounds: CatalogSearcher, and the local selection preamble'
---
## What

Three cards landed in the sibling packages on 2026-09-10. Two workarounds in this package are now duplicate work. Remove them. Do not change what the flash model sees until you measure the change.

The dependency versions after `swift package update`:

| package | before | after |
|---|---|---|
| FoundationModelsRanker | 5ab7b1a | 2f0bd16 |
| FoundationModelsMetadataRegistry | 9e196cd | 9a8f6c4 |

Update the pins of the root package and of the nested `IntegrationTests` package. The two packages hold their own `Package.resolved` file. A build of the nested package against the old pins is a false green.

## Why the two workarounds are dead weight

**CatalogSearcher.** `Sources/FoundationModelsMultitool/Discovery/CatalogSearcher.swift` builds a `MetadataSearcher` synchronously with an embedder (lines 66-67). It then calls `fill()` before each search (line 80). `fill()` runs `MetadataSearcher.update(items:)` one time (line 123). The registry now does this work itself. The synchronous initializer sets `firstSearchCatchUp = .pending` (`MetadataSearcher.swift:267`), and `search(intent:limit:)` calls `catchUpEmbeddingsBeforeFirstSearch()` first (`MetadataSearcher+Search.swift:145`). The doc comment of `CatalogSearcher` (lines 23-28) names registry card `^8c4wtra` as the condition to delete the file. That card landed.

**selectionPreamble.** `Sources/FoundationModelsMultitool/Discovery/SearchToolsTool.swift:306`. This constant exists because the old ranker default made the 4B model answer an empty list. The new ranker default (`SelectionConfig.swift:182-187`) holds the decisive sentence word for word: "Prefer the closest candidates over an empty answer; answer with an empty list only when no candidate is related to the task at all." Ranker card `^zxm99zs` landed. The two texts now differ only in the noun. The local text says "the functions a program can call". The ranker default says "the items available to do a task", and it adds "Use only the ids shown."

## The danger

This package gives the tools to an agent. If discovery gets worse, the agent finds no way to write a file, and a bench run gives an empty patch. Card `^zqz1zan` records that failure. These rules hold the danger:

1. Make the two changes in two commits. One commit for each change. A regression must point at one change.
2. Run the gated suite before and after each change. The unit tests use a stub embedder and a scripted model. They cannot see a change in what the flash model answers. Only the gated suite can.
3. Do not delete a test to make a step green. Do not make an assertion weaker.
4. Do not edit a package checkout under `.build/checkouts`.
5. The bundle build must stay synchronous. `RegistryBundle.init` runs under the holder lock at each surface swap, and `makeSessionToolsAndStaging` starts no task. `SurfaceRefresher.swift` states that rule. The registry catch-up obeys it, because the catch-up runs inside `search`, not inside the initializer.

## Step 1: delete CatalogSearcher

`CatalogSearcher` is a type in these signatures. Change each one to `MetadataSearcher<APISurface.Entry>`:

- `RegistryBundle.swift:75` `hintSearcher`, `:79` `discoverySearcher`, `:97` the build call.
- `SearchToolsTool.swift:76` `Catalog.fixed`, `:115` and `:127` the two initializers, `:170` `makeSearcher`, `:192` `resolveCatalog`.
- `UnknownToolHint.swift:189`, `:329`, `:394`.
- `Tests/FoundationModelsMultitoolTests/UnknownToolHintTests.swift:281` and `:324`. Both wrap a searcher that is already built. Pass that searcher directly.

Then delete the file, with `CatalogSearcher` and `CatalogEmbedding` in it.

**Watch the diagnostics.** `fill()` calls `update(items:)`. The registry catch-up calls `catchUpEmbeddings(...)`. The two paths embed the same blocks, but they can report different diagnostics and can call the embedder a different number of times. `Tests/FoundationModelsMultitoolTests/DiscoveryEmbedderTests.swift` holds six tests with a `RecordingEmbedder`. Keep each test on the contract it states, not on the old call count. The contract is this: the host embedder is used, the catalog is embedded one time, the cosine signal joins the ranking, and no search reports `no embedder configured`. If a count changes, record the old count and the new count on this card, and say why the new count is correct.

**Watch the failure path.** Today an embed that fails leaves the searcher keyword-only for the life of the bundle, and the next surface swap builds a bundle that embeds again. The registry marks the catch-up `.done` on every exit, a failure included. Confirm that a failed embed still leaves the searcher usable, and that a new bundle still tries again. A test must hold this.

## Step 2: delete selectionPreamble, only if the measurement permits it

**Measure first.** The file `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/PreambleMeasurementScratch.swift` is in the tree and does this measurement. It runs each wording three rounds on `mlx-community/Qwen3-4B-4bit`. Use it, or write the same measurement. Three rounds are necessary, because one round of a 4B model is not evidence.

Compare the local `selectionPreamble` against `String.selectionDefault`, over the ten queries of `agentSurfaceQueries`.

**The decision rule.** Delete the constant only when the ranker default holds all three of these, in every one of the three rounds:

- All ten queries answer with at least one match.
- Queries 4 to 9 each hold `shell.execute`, `files.write` or `files.edit`.
- The prefix stays under 9,000 characters.

If the default fails any one of them, keep the constant. Then correct its doc comment instead, and record the measurement on this card. A kept constant is a correct result of this step, not a failure.

**When you delete it**, these places name it:

- `SearchToolsTool.swift:395`, the wiring. Drop the `preamble:` argument, so `SelectionConfig` takes its own default.
- `SearchToolsTool.swift:300-312`, the constant and its doc comment.
- `Tests/FoundationModelsMultitoolTests/SearchToolsToolTests.swift:208-209`. Line 209 states that the preamble is NOT the default. That line is a guard against the old defect. Do not simply delete the guard. Replace it with a test that the tier is seeded with a preamble that holds the empty-answer sentence. The gated suite is the other half of the guard.
- `AgentSurfaceDiscoveryTests.swift:170`, the prefix measurement, and its doc comment at line 82. Both name the constant.

## Not in this card

`MetadataDiagnostic.retrievalCut` is dead in the ranker now, because the selection tier never cuts the catalog. A search of this package finds no branch on that case, so there is nothing to remove here.

## Acceptance Criteria

- [ ] The pins of the root package and of the `IntegrationTests` package name ranker `2f0bd16` and registry `9a8f6c4`, or a later commit of each.
- [ ] `CatalogSearcher.swift` is deleted, and no file names `CatalogSearcher` or `CatalogEmbedding`.
- [ ] The gated suite passes after step 1, and the counts of the ten queries are on this card.
- [ ] The three-round measurement of the two preambles is on this card, with the raw ids of each query.
- [ ] The constant is deleted, or it is kept with the measurement that says why. This card states which.
- [ ] The gated suite passes after step 2, and the counts and the prefix size are on this card.
- [ ] `PreambleMeasurementScratch.swift` is deleted when the measurement is recorded.

## Tests

- [ ] `swift test` at the root: no failure, no warning.
- [ ] `swift build --package-path IntegrationTests`: no error.
- [ ] `swift test --package-path IntegrationTests --no-parallel --filter AgentSurfaceDiscoveryTests`: passes.
- [ ] A test holds the failed-embed path of step 1.
- [ ] A test holds the empty-answer guard of step 2.

#discovery #search-tools #cleanup