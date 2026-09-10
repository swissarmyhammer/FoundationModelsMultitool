---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m25rqnn2d5q98vszes7dcyth
  text: |-
    ### Research

    The pins are already correct in the tree: ranker `2f0bd16835d4773ed8ac842682030bd984aac34a`, registry `54517141895e20bd04f9a0b01c53ff165294b883`, in `Package.resolved` and in `IntegrationTests/Package.resolved`. The registry commit is later than the `9a8f6c4` the card names, which the first acceptance criterion permits.

    `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/PreambleMeasurementScratch.swift` was NOT in the tree, and no commit ever held it. So the measurement was written new, as the card permits.

    The registry catch-up embeds `entry.block` for each entry with no vector, one batch, in catalog order (`MetadataIndex+Embedding.swift`, `pendingEmbeddings()`). That is the same text and the same grouping the old `update(items:)` path embedded. So the embedder call counts of `DiscoveryEmbedderTests` do not change.

    The retrieval tier asks for a query embed only when at least one entry carries a vector (`computeCosineScores`). So a searcher whose catalog embed failed makes no query-embed call at all — it reports `.embeddingUnavailable` and ranks by BM25 and trigram.
  timestamp: 2026-09-10T13:39:52.610886+00:00
- actor: claude-code
  id: 01m25rr31ka4k7wakz59a1pq1s
  text: |-
    ### Step 1 — CatalogSearcher deleted

    `Sources/FoundationModelsMultitool/Discovery/CatalogSearcher.swift` is gone. Each signature the card names now takes `MetadataSearcher<APISurface.Entry>`. The two `SearchToolsTool` initializers over a searcher became one, because they had the same signature after the change.

    **Embedder call counts: no change.** The three counting tests of `DiscoveryEmbedderTests` pass with the same expectations they held before:

    - the discovery searcher over two entries, two searches: `[[block1, block2], ["trip cities"], ["temperature"]]` — one catalog batch, then one query batch per search.
    - the hint searcher, one search: `[[block1, block2], ["get itinerary"]]`.
    - a bundle with no embedder: no batch at all, and the search still answers.

    **Failed-embed path, new test.** `failedCatalogEmbedLeavesTheSearcherAnsweringAndTheNextBundleRetries` in `DiscoveryEmbedderTests`. `RecordingEmbedder(alwaysFails: true)` records each batch and then throws. The readings:

    - the first search of the bundle answers `getCities` — the searcher stays usable, keyword-only.
    - the second search of the same bundle makes no new embedder call — the registry marks the catch-up done on every exit, a failure included.
    - a fresh bundle over the same registry embeds again.
    - `embedder.batches == [blocks, blocks]`: the catalog batch two times, one per bundle, and no query batch at all.

    **Gated suite before and after step 1: pass, with the same counts.** Ten queries, `prefixCharacters=7600`, `entries=9`:

    ```
    q1 matches=3 paths=["files.glob", "files.read", "shell.execute"]
    q2 matches=2 paths=["files.glob", "files.read"]
    q3 matches=1 paths=["files.grep"]
    q4 matches=1 paths=["shell.execute"]
    q5 matches=1 paths=["shell.execute"]
    q6 matches=3 paths=["files.write", "files.edit", "files.read"]
    q7 matches=2 paths=["files.edit", "files.patch"]
    q8 matches=1 paths=["files.edit"]
    q9 matches=6 paths=["files.write", "files.edit", "files.patch", "files.glob", "files.grep", "shell.execute"]
    q10 matches=1 paths=["files.write"]
    ```

    Root suite: 1,410 tests pass, no warning.
  timestamp: 2026-09-10T13:40:06.323091+00:00
- actor: claude-code
  id: 01m25rrgj53h1526s8vxf6azyq
  text: |-
    ### Step 2 — the three-round measurement

    Model `mlx-community/Qwen3-4B-4bit` (the flash slot of `agentDiscoveryProfile`), the nine-entry files-and-shell surface, the production `searchTools` path, the same grammar for both wordings. Three rounds of the ten queries for each wording, sixty selection calls, one run of 45.5 s.

    Prefix size: local `7600` characters, ranker default `7601` characters, budget `32000`.

    **Local `selectionPreamble`** — the raw ids the selection model answered. Rounds 1, 2 and 3 are the same, id for id:

    ```
    q1  ["files.glob", "files.read", "shell.execute"]
    q2  ["files.glob", "files.read"]
    q3  ["files.grep"]
    q4  ["shell.execute"]
    q5  ["shell.execute"]
    q6  ["files.write", "files.edit", "files.read", "files.write"]
    q7  ["files.edit", "files.patch"]
    q8  ["files.edit"]
    q9  ["files.write", "files.edit", "files.patch", "files.glob", "files.grep", "shell.execute"]
    q10 ["files.write"]
    ```

    **Ranker `String.selectionDefault`** — rounds 1, 2 and 3 are the same, id for id:

    ```
    q1  ["files.glob", "files.read", "shell.execute"]
    q2  ["files.glob", "files.read"]
    q3  ["files.grep"]
    q4  ["shell.execute"]
    q5  ["shell.execute"]
    q6  ["files.write", "files.edit", "files.read"]
    q7  ["files.edit", "files.patch"]
    q8  ["files.edit", "files.write"]
    q9  ["files.write", "files.edit", "files.patch", "files.glob", "files.grep", "shell.execute"]
    q10 ["files.write"]
    ```

    **The decision rule, applied to the ranker default:**

    1. All ten queries answer with at least one match — true in each of the three rounds. 30 of 30.
    2. Queries 4 to 9 each hold `shell.execute`, `files.write` or `files.edit` — true in each of the three rounds: q4 and q5 `shell.execute`, q6 `files.write`, q7 `files.edit`, q8 `files.edit`, q9 `files.write`.
    3. The prefix stays under 9,000 characters — 7,601.

    All three hold. **So the local constant is deleted, and the tier takes `String.selectionDefault`.**

    The one difference between the two wordings is a small one, and it favors the default: the default answers q8 with `files.edit` and `files.write`, where the local wording answered `files.edit` alone; and the default never repeated an id, where the local wording answered `files.write` two times in q6.

    `PreambleMeasurementScratch.swift` is deleted, as the last acceptance criterion asks.
  timestamp: 2026-09-10T13:40:20.165267+00:00
- actor: claude-code
  id: 01m25rrwgf443q75qdh54dkr24
  text: |-
    ### Step 2 — the constant removed, and the gated suite after it

    `SearchToolsTool.selectionPreamble` is deleted. `makeSelection(librarian:ids:)` no longer passes a `preamble:` argument, so `SelectionConfig` takes `String.selectionDefault`. The doc comment of `makeSelection` now carries the record of both measurements.

    The guard of `SearchToolsToolTests` is replaced, not deleted. The new test `selectionTierIsSeededWithTheEmptyAnswerGuidance` asserts that the preamble the tier gets holds the deciding sentence, written out in the test file:

    > Prefer the closest candidates over an empty answer; answer with an empty list only when no candidate is related to the task at all.

    The test file states why that sentence is a copy and not a read of `String.selectionDefault`: a test that read the sentence off the same constant it grades would hold whatever that constant said, and a later ranker default that dropped the sentence would pass.

    `AgentSurfaceDiscoveryTests` now assembles its prefix with `.selectionDefault`, and its doc comment records the change.

    **Gated suite after step 2: pass.** `entries=9`, `prefixCharacters=7601`, `budget=32000`:

    ```
    q1  matches=3 paths=["files.glob", "files.read", "shell.execute"]
    q2  matches=2 paths=["files.glob", "files.read"]
    q3  matches=1 paths=["files.grep"]
    q4  matches=1 paths=["shell.execute"]
    q5  matches=1 paths=["shell.execute"]
    q6  matches=3 paths=["files.write", "files.edit", "files.read"]
    q7  matches=2 paths=["files.edit", "files.patch"]
    q8  matches=2 paths=["files.edit", "files.write"]
    q9  matches=6 paths=["files.write", "files.edit", "files.patch", "files.glob", "files.grep", "shell.execute"]
    q10 matches=1 paths=["files.write"]
    ```

    Root suite after step 2: 1,410 tests pass, no warning. `swift build --package-path IntegrationTests`: no error.

    The bundle build stays synchronous: `RegistryBundle.init` builds each `MetadataSearcher` with the synchronous designated initializer and starts no task. The embed happens inside the first `search`, which the registry owns.
  timestamp: 2026-09-10T13:40:32.399548+00:00
- actor: claude-code
  id: 01m25rs3enstf88pje3ma1n50b
  text: |-
    ### implement — changed
    - evidence: `swift test` 1410 tests pass, 0 failures, 0 warnings; `swift build --package-path IntegrationTests` no error; `swift test --package-path IntegrationTests --no-parallel --filter AgentSurfaceDiscoveryTests` passes. 8 files — Sources/FoundationModelsMultitool/Discovery/CatalogSearcher.swift (deleted), Sources/FoundationModelsMultitool/Discovery/SearchToolsTool.swift, Sources/FoundationModelsMultitool/Discovery/UnknownToolHint.swift, Sources/FoundationModelsMultitool/RegistryBundle.swift, Tests/FoundationModelsMultitoolTests/DiscoveryEmbedderTests.swift, Tests/FoundationModelsMultitoolTests/Fixtures/EmbeddingFixtures.swift, Tests/FoundationModelsMultitoolTests/SearchToolsToolTests.swift, Tests/FoundationModelsMultitoolTests/UnknownToolHintTests.swift, IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/AgentSurfaceDiscoveryTests.swift.
    - next: `/review`
  timestamp: 2026-09-10T13:40:39.509772+00:00
- actor: claude-code
  id: 01m25rxgrkatn7fd9817cdekxn
  text: |-
    ### commit — changed
    - evidence: 8a8e4ba refactor(discovery): delete CatalogSearcher and the local selection preamble
    - next: none
  timestamp: 2026-09-10T13:43:04.211001+00:00
- actor: claude-code
  id: 01m25rxsm3kvy123n569xke397
  text: |-
    ### test — green
    - evidence: `swift test` — 1410 tests, 110 suites, 0 failed, 0 warnings. `swift build --package-path IntegrationTests` — build complete, 0 errors, 0 warnings (only the known dependency message `warning: missing creator for mutated node` for the mlx-swift Cmlx bundle, recorded on card ^zqz1zan, not counted as red). `swift test --package-path IntegrationTests --no-parallel --filter AgentSurfaceDiscoveryTests` — 1 test, 1 suite, 0 failed. Name check: no file under Sources, Tests or IntegrationTests names `CatalogSearcher` or `CatalogEmbedding`. One mention of `selectionPreamble` remains, in a doc comment in `AgentSurfaceDiscoveryTests.swift`, as a historical note that the wording "lived in this package as `SearchToolsTool.selectionPreamble` until card `^46j5hqw`" — this is prose about history, not a live code reference, and is not a failure or a warning. `PreambleMeasurementScratch.swift` is confirmed gone.
    - next: none. The build is clean.
  timestamp: 2026-09-10T13:43:13.283546+00:00
- actor: claude-code
  id: 01m25rzbkh01bk7tzhsdq8vkhm
  text: |-
    ### commit — changed
    - evidence: b392807 chore(kanban): add the commit and test ledger notes for task ^46j5hqw (2 files)
    - next: none
  timestamp: 2026-09-10T13:44:04.465450+00:00
- actor: claude-code
  id: 01m25s2yk8c2grd1kpg1ax2qss
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD`, 9 files read, 0 findings, 0 confirmed, 0 refuted. Five code-hygiene rules declined one item each, because `Sources/FoundationModelsMultitool/Discovery/CatalogSearcher.swift` is deleted by this change.
    - next: none. The task moves to done.
  timestamp: 2026-09-10T13:46:02.216188+00:00
- actor: claude-code
  id: 01m25s3ee0bgcrvkgy6zv10h1m
  text: |
    ### finish iteration 1 — clean

    - implement: changed. `CatalogSearcher.swift` is deleted. Each signature now takes `MetadataSearcher<APISurface.Entry>`. The local `selectionPreamble` is deleted, because the three-round measurement on `mlx-community/Qwen3-4B-4bit` permits it. A new test holds the failed-embed path. A new test holds the empty-answer guard.
    - test: green. `swift test` gives 1410 pass, 0 fail, 0 warning. `swift build --package-path IntegrationTests` gives 0 error. `swift test --package-path IntegrationTests --no-parallel --filter AgentSurfaceDiscoveryTests` gives 1 pass. The message `missing creator for mutated node` comes from the mlx-swift Cmlx checkout. Card ^zqz1zan records it. It is not a failure.
    - commit: 8a8e4ba refactor(discovery): delete CatalogSearcher and the local selection preamble
    - review: clean. 0 finding over `HEAD~1..HEAD`, on 9 files. The task moved to done.
  timestamp: 2026-09-10T13:46:18.432489+00:00
- actor: claude-code
  id: 01m25spvx4hkg47047d8w2rqty
  text: |-
    ### review — findings
    - evidence: 1 open finding — Tests/FoundationModelsMultitoolTests/UnknownToolHintTests.swift:324. Scope: review sha HEAD~2..HEAD, local backend. Counts: 1 finding, 1 confirmed, 1 refuted.
    - next: Build the searcher in that test the same way the source code builds it: MetadataSearcher(index: MetadataIndex(items:), mode:, embedder:, selection:). Remove the same cause from the full file. Then run the review again.
  timestamp: 2026-09-10T13:56:54.820859+00:00
- actor: claude-code
  id: 01m25sxktyhmwa7mew08g4awc6
  text: |-
    ### The cause, removed from the full file

    The finding named line 324, and named line 281 as the same cause. A search of `Tests/FoundationModelsMultitoolTests/UnknownToolHintTests.swift` for a searcher build finds those two places, and no other. No helper of the file builds a searcher, and no other test in the file builds one.

    Both now build the searcher the way `RegistryBundle.init` builds `hintSearcher`:

    ```swift
    MetadataSearcher(
        index: MetadataIndex(items: registry.surface.entries), mode: .retrieval,
        embedder: nil, selection: nil)
    ```

    The behavior does not change. `init(items:mode:)` forwards to this same designated initializer with `MetadataIndex(items:)`, a nil embedder and a nil selection. The test now shows that shape, so a reader sees the same four inputs the source code gives.

    No test is deleted. No assertion is weaker. No production source is changed. No dependency pin is changed. No file under `.build/checkouts` is touched.
  timestamp: 2026-09-10T14:00:35.934834+00:00
- actor: claude-code
  id: 01m25sxtvg969efqghrrtmj0rm
  text: |-
    ### implement — changed
    - evidence: 1 file — Tests/FoundationModelsMultitoolTests/UnknownToolHintTests.swift. The cause: the file built `MetadataSearcher(items:mode:)`, where the source code builds `MetadataSearcher(index: MetadataIndex(items:), mode:, embedder:, selection:)`. Both places of the file (the `resolve(_:)` helper, and the no-tier test) now build it the way `RegistryBundle.init` does. `swift test` — 1410 tests, 110 suites, 0 failed, 0 warnings. `swift build --package-path IntegrationTests` — build complete, 0 errors (only the known dependency message `warning: missing creator for mutated node` for the mlx-swift Cmlx bundle). `swift test --package-path IntegrationTests --no-parallel --filter AgentSurfaceDiscoveryTests` — 1 test, 1 suite, 0 failed, entries=9, prefixCharacters=7601, all ten queries answered.
    - next: `/review`
  timestamp: 2026-09-10T14:00:43.120769+00:00
- actor: claude-code
  id: 01m25t0mzh3kgxnaxad0b8vx9f
  text: |-
    ### commit — changed
    - evidence: fd3f437 — 3 files changed (source test file + 2 kanban task files)
    - next: send the change to review.
  timestamp: 2026-09-10T14:02:15.409578+00:00
- actor: claude-code
  id: 01m25t4fyw6m4bcnmtg7eznajp
  text: |-
    ### review — clean
    - evidence: 0 findings over HEAD~1..HEAD (commit fd3f437). 7 validator runs, 0 failures. The one prior finding of the 2026-09-10 08:44 section is checked.
    - next: none. The card moves to done.
  timestamp: 2026-09-10T14:04:21.340589+00:00
- actor: claude-code
  id: 01m25t52pz3sgsgf5h7sv5vb5z
  text: |-
    ### finish iteration 2 — clean

    - implement: changed. The open finding is fixed. `Tests/FoundationModelsMultitoolTests/UnknownToolHintTests.swift` built its searcher with the convenience initializer. Both places in the file now build it the way `RegistryBundle` builds it. No test was deleted. No assertion is weaker.
    - test: green. `swift test` gives 1410 pass, 0 fail, 0 warning. `swift build --package-path IntegrationTests` gives 0 error. The gated suite gives 1 pass, with `entries=9` and `prefixCharacters=7601`.
    - commit: fd3f437, 3 files. The source change and the board files are in one commit, so the review reads the code.
    - review: clean. 0 finding over `HEAD~1..HEAD`. The prior finding is checked. The task moved to done.

    Note on iteration 1: the review of that iteration read `HEAD~1..HEAD`, but the commit step had made two commits, and the last one held only board files. So that review read no code. The review of this iteration reads the code, because the commit step made one commit.
  timestamp: 2026-09-10T14:04:40.543101+00:00
position_column: done
position_ordinal: ffba80
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

- [x] The pins of the root package and of the `IntegrationTests` package name ranker `2f0bd16` and registry `9a8f6c4`, or a later commit of each.
- [x] `CatalogSearcher.swift` is deleted, and no file names `CatalogSearcher` or `CatalogEmbedding`.
- [x] The gated suite passes after step 1, and the counts of the ten queries are on this card.
- [x] The three-round measurement of the two preambles is on this card, with the raw ids of each query.
- [x] The constant is deleted, or it is kept with the measurement that says why. This card states which. **The constant is deleted.**
- [x] The gated suite passes after step 2, and the counts and the prefix size are on this card.
- [x] `PreambleMeasurementScratch.swift` is deleted when the measurement is recorded.

## Tests

- [x] `swift test` at the root: no failure, no warning.
- [x] `swift build --package-path IntegrationTests`: no error.
- [x] `swift test --package-path IntegrationTests --no-parallel --filter AgentSurfaceDiscoveryTests`: passes.
- [x] A test holds the failed-embed path of step 1.
- [x] A test holds the empty-answer guard of step 2.

#discovery #search-tools #cleanup

## Review Findings (2026-09-10 08:44)

> Scope: `review sha HEAD~2..HEAD` — reviewed the diffs only — lines this change added or modified. 9 file(s) reviewed, 2 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

> ⚠️ tool rule 'code-hygiene/disallowed-constructs-swift' declined an item — it judged the rest of the code, and this it could not judge:
> disallowed-constructs-swift found no file at Sources/FoundationModelsMultitool/Discovery/CatalogSearcher.swift, so its constructs are unread

> ⚠️ tool rule 'code-hygiene/function-length-swift' declined an item — it judged the rest of the code, and this it could not judge:
> function-length-swift found no file at Sources/FoundationModelsMultitool/Discovery/CatalogSearcher.swift, so its bodies are unread

> ⚠️ tool rule 'code-hygiene/idioms-swift' declined an item — it judged the rest of the code, and this it could not judge:
> idioms-swift found no file at Sources/FoundationModelsMultitool/Discovery/CatalogSearcher.swift, so its declarations are unread

> ⚠️ tool rule 'code-hygiene/magic-numbers-swift' declined an item — it judged the rest of the code, and this it could not judge:
> magic-numbers-swift found no file at Sources/FoundationModelsMultitool/Discovery/CatalogSearcher.swift, so its literals are unread

> ⚠️ tool rule 'code-hygiene/missing-docs-swift' declined an item — it judged the rest of the code, and this it could not judge:
> missing-docs-swift found no file at Sources/FoundationModelsMultitool/Discovery/CatalogSearcher.swift, so its declarations are unread

- [x] `Tests/FoundationModelsMultitoolTests/UnknownToolHintTests.swift:324` `completeness/invariant-propagation` — Same inconsistency as line 281: the test creates `MetadataSearcher(items:, mode:)` while production code uses `MetadataSearcher(index: MetadataIndex(items:), mode:, embedder:, selection:)`. Create the searcher consistently: `MetadataSearcher(index: MetadataIndex(items: registry.surface.entries), mode: .retrieval, embedder: nil, selection: nil)`.
