---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m26ns8fzrnzb080sgsv7nyfk
  text: |-
    Research done, and it changes the shape of the question the card asks.

    `renderBlock()` does three jobs in the registry, not two:

    - `MetadataIndex.buildEntry(item:)` tokenizes and trigrams it (`Catalog/MetadataIndex.swift`).
    - `MetadataIndex.pendingEmbeddings()` hands it to the embedder (`Catalog/MetadataIndex+Embedding.swift`).
    - `MetadataSearcher.matches(fromHits:in:)` gives it back as `Match.block`, which `SearchToolsTool` splices verbatim into the main session.

    So the third job holds the other two. A consumer cannot make the keyword half read the description without also taking the signature away from the text the main model reads to write the call. That rules out the description-for-both setting as something this package could ship, whatever it measures.

    The registry gives no way to use one text for keyword ranking and another for the embedder, exactly as the card expects. The measurement therefore uses an instrument in the integration target and not a mechanism here: a `TextEmbedding` that swaps the block for the summary block on the way in. The registry hands the embedder the same text it indexes, so a swap at that door is the only way to read the split, and a query never matches a block, so a query travels unchanged.

    The measurement runs on `plumbingProbeProfile`, not on `agentDiscoveryProfile`. Nothing generates: the selection tier is off, so the reading is the embedder's, and every profile of this target names the same `CLIRunner.embeddingModel`. That is the test `plumbingProbeProfile` states for which suites may take it, and `UnknownToolHintLiveTests` takes it for the same reason.

    The queries and the grading types come from the two suites that own them. The new suite reads `agentSurfaceQueries`, `heldOutQueries` and `GradedDiscoveryQuery` and writes no query of its own.
  timestamp: 2026-09-10T22:07:33.375851+00:00
- actor: claude-code
  id: 01m26nt92hnxevkk0gj0c7qd31
  text: |-
    ## The measurement

    `RetrievalTextSurfaceDiscoveryTests`, in the nested `IntegrationTests` package. Three settings over the same nine-entry files-and-shell surface, the same embedder and the same twenty-five queries, with the selection tier switched off — `.retrieval` mode, no `SelectionConfig` — so only retrieval answers. Each query asks for the whole catalog, so every declared path has a place to report. Run 2026-09-10 on `plumbingProbeProfile`. Two runs printed the same numbers to the digit: nothing on this path samples.

    Surface size: 9 entries, 18,720 characters of block against 9,057 characters of summary block.

    ### Where the correct tool ranks, for each query, in each setting

    Each cell holds every path a reader declared correct for that query, with the place it took. A dash would mean no signal ranked it; there is no dash, so every declared path ranked in every setting.

    | query | text | block/block | description/description | block/description |
    |---|---|---|---|---|
    | agentSurface q1 | Search the astropy codebase for files, read code, and run tests | files.glob:2 files.grep:1 files.read:6 shell.execute:3 | files.glob:2 files.grep:1 files.read:5 shell.execute:4 | files.glob:2 files.grep:1 files.read:6 shell.execute:4 |
    | agentSurface q2 | list files and read file contents | files.glob:4 files.read:2 | files.glob:3 files.read:1 | files.glob:4 files.read:1 |
    | agentSurface q3 | grep search for text pattern in files | files.grep:1 | files.grep:1 | files.grep:1 |
    | agentSurface q4 | run a shell command or python script, execute code | shell.execute:1 | shell.execute:1 | shell.execute:1 |
    | agentSurface q5 | run pytest tests, execute | shell.execute:1 | shell.execute:1 | shell.execute:1 |
    | agentSurface q6 | write file, edit file, create file | files.edit:3 files.patch:2 files.write:1 | files.edit:2 files.patch:3 files.write:1 | files.edit:2 files.patch:3 files.write:1 |
    | agentSurface q7 | edit code, modify source file, patch | files.edit:4 files.patch:1 | files.edit:2 files.patch:1 | files.edit:2 files.patch:1 |
    | agentSurface q8 | apply changes to a file, save file contents | files.edit:5 files.patch:1 files.write:3 | files.edit:1 files.patch:2 files.write:3 | files.edit:1 files.patch:2 files.write:3 |
    | agentSurface q9 | file operations: create, write, append, delete, move | files.edit:6 files.patch:1 files.write:2 shell.execute:5 | files.edit:4 files.patch:1 files.write:2 shell.execute:5 | files.edit:3 files.patch:1 files.write:2 shell.execute:5 |
    | agentSurface q10 | create a new text file with given content on disk | files.patch:2 files.write:1 | files.patch:2 files.write:3 | files.patch:1 files.write:3 |
    | heldOut q1 | show me the files and folders in this checkout | files.glob:4 shell.execute:3 | files.glob:1 shell.execute:7 | files.glob:2 shell.execute:8 |
    | heldOut q2 | i need to read the source file where the defect lives | files.read:1 | files.read:1 | files.read:1 |
    | heldOut q3 | find every place in the code that mentions this function name | files.grep:3 | files.grep:2 | files.grep:4 |
    | heldOut q4 | open a file and look at one region of it closely | files.read:1 | files.read:1 | files.read:1 |
    | heldOut q5 | change a few lines in an existing source file | files.edit:6 files.patch:3 | files.edit:5 files.patch:3 | files.edit:5 files.patch:3 |
    | heldOut q6 | rewrite the whole contents of a module | files.patch:4 files.write:1 | files.patch:5 files.write:1 | files.patch:3 files.write:2 |
    | heldOut q7 | create a new file to hold a regression test | files.patch:3 files.write:1 | files.patch:2 files.write:1 | files.patch:2 files.write:1 |
    | heldOut q8 | i want to run the project test suite now | shell.execute:1 | shell.execute:2 | shell.execute:2 |
    | heldOut q9 | run only the one test that reproduces the bug | shell.execute:4 | shell.execute:3 | shell.execute:4 |
    | heldOut q10 | i need to see what the failing test printed | shell.getLines:1 shell.grepHistory:2 | shell.getLines:1 shell.grepHistory:2 | shell.getLines:1 shell.grepHistory:2 |
    | heldOut q11 | run a shell command in the project directory | shell.execute:1 | shell.execute:2 | shell.execute:2 |
    | heldOut q12 | read the log file that the last run wrote | files.read:1 shell.getLines:3 | files.read:1 shell.getLines:2 | files.read:1 shell.getLines:2 |
    | heldOut q13 | delete a leftover temporary directory | shell.execute:1 | shell.execute:2 | shell.execute:2 |
    | heldOut q14 | remove a scratch file i made earlier | files.patch:1 shell.execute:7 | files.patch:1 shell.execute:8 | files.patch:1 shell.execute:9 |
    | heldOut q15 | check which source files i have changed so far | shell.execute:5 | shell.execute:5 | shell.execute:5 |

    ### The totals of each setting

    | setting | group | rank 1 | top 3 | mean best rank | declared paths in the top 3 |
    |---|---|---|---|---|---|
    | block/block | agentSurface | 9/10 | 10/10 | 1.10 | 17/23 |
    | block/block | heldOut | 10/15 | 13/15 | 1.87 | 16/22 |
    | description/description | agentSurface | 9/10 | 10/10 | 1.10 | 19/23 |
    | description/description | heldOut | 8/15 | 14/15 | 1.80 | 17/22 |
    | block/description | agentSurface | 10/10 | 10/10 | 1.00 | 19/23 |
    | block/description | heldOut | 6/15 | 12/15 | 2.13 | 16/22 |

    ## The choice: the full block, for the keyword index and the embedder alike

    The card thought the embedder was the weak half. The held-out group says the opposite. Give the embedder the description alone and it becomes the worst of the three settings there, on all three counts: 6 against 10 at rank one, 12 against 13 in the top three, a mean of 2.13 against 1.87. It wins only on the ten queries a coding agent wrote while it hunted for these tools, and those queries are full of the words the signature carries.

    The description-for-both setting reads a little better on the held-out group (14 in the top three against 13, a mean of 1.80 against 1.87) and costs half as much to embed. It is still not taken, because `renderBlock()` also gives the main session the text it reads to write the call. The gain is inside one rank place; the loss would be the call site.

    So the shipped conformance does not change, and it is now a measured choice instead of a default. The choice and these numbers stand in the doc comment of `Sources/FoundationModelsMultitool/Surface/APISurface+SearchableMetadata.swift`.

    ## The registry card

    `^kh2ttmm`, in `FoundationModelsMetadataRegistry`, at `.kanban/tasks/01M26P0000R9VXQ7B3DKH2TTMM.md`. It asks for `renderIndexedText()` and `renderEmbeddedText()`, each defaulting to `renderBlock()`, so a consumer can narrow either retrieval half without touching the verbatim block. It carries this measurement as its reason, and it names the point that `Entry.blockHash` must then key on the embedded text or a changed embedded text keeps a stale vector.
  timestamp: 2026-09-10T22:08:06.737074+00:00
- actor: claude-code
  id: 01m26nxb1y60ck6gthfmzz7tbj
  text: |-
    ### implement — changed
    - evidence: three settings measured with the selection tier off, over the ten queries of `^zqz1zan` and the fifteen held-out queries of `^kn9ay20`, on 2026-09-10, and repeated to the digit. block/block: agentSurface 9/10 at rank one, 10/10 in the top three, mean best rank 1.10; heldOut 10/15, 13/15, 1.87. description/description: agentSurface 9/10, 10/10, 1.10; heldOut 8/15, 14/15, 1.80. block/description: agentSurface 10/10, 10/10, 1.00; heldOut 6/15, 12/15, 2.13. Every declared path of every query ranked in every setting. Surface size 9 entries, 18,720 block characters against 9,057 summary characters. Choice: keep the full block for the keyword index and the embedder alike, because the split the card suspected would help is the worst of the three on the held-out group, and because the description-for-both setting cannot be taken at all — `renderBlock()` also gives the main session the text it reads to write the call. Registry card `^kh2ttmm` asks for the two seams that would open that door. Files: `Sources/FoundationModelsMultitool/Surface/APISurface+SearchableMetadata.swift` (doc comment: the choice and the numbers), new `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/RetrievalTextSurfaceDiscoveryTests.swift`, new `FoundationModelsMetadataRegistry/.kanban/tasks/01M26P0000R9VXQ7B3DKH2TTMM.md` and its ledger. Tests: root `swift test` 1,422 tests in 113 suites, all green, no warning; `swift build --package-path IntegrationTests` clean; the five gated discovery suites 5 tests in 5 suites, all green (agentSurface 19 correct and 3 undeclared in each of three rounds; heldOut 16 correct and 2 undeclared in each of three rounds; no-description, over-budget and the new retrieval-text suite green). No production behavior changed: the shipped conformance is the same code, and the card is now a measured decision instead of a default.
    - next: review. One thing found on the way and put on its own card `^fdaxnjw`: the doc comment of `HeldOutSurfaceDiscoveryTests` says the suite is red at 9 of 22, and it now scores 16 in every round and passes, most likely because card `^p06rh7z` rewrote the nine descriptions.
  timestamp: 2026-09-10T22:09:47.070147+00:00
- actor: claude-code
  id: 01m26p0c6d0bfhkw9hr55faeb2
  text: |-
    ### commit — changed
    - evidence: 2d3b21ba45b6c01b2e199f80c61f5fd23281ed45, 10 files changed, 723 insertions(+), 10 deletions(-)
    - next: review
  timestamp: 2026-09-10T22:11:26.541080+00:00
- actor: claude-code
  id: 01m26pdaf9y61r5zpdb6srt25t
  text: |-
    ### review — findings
    - evidence: 2 findings over HEAD~1..HEAD — IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/RetrievalTextSurfaceDiscoveryTests.swift:184, RetrievalTextSurfaceDiscoveryTests.swift:185. Both are `code-hygiene/magic-numbers-swift`: replace the magic numbers with named constants.
    - next: Correct the cause in the full file, not the two lines alone. Then run the review again. The card stays in review until the findings are closed.
  timestamp: 2026-09-10T22:18:30.761157+00:00
- actor: claude-code
  id: 01m26pkfqb1fx297e72bka9dt0
  text: |-
    The card came back to doing to close the two review findings.

    The rule behind both is `swiftlint no_magic_numbers`, with `allowed_numbers: [0, 1, -1, 100]`. I ran that rule over the whole file with its own configuration before I made a change, so I would see every literal it reads and not the two lines of the review alone. The run read exactly two violations, at the two `shippedTopPlaceLevel:` arguments of `retrievalTextGroups`.

    Four numbers now carry a name:

    - `shippedAgentSurfaceTopPlaceLevel` (10) and `shippedHeldOutTopPlaceLevel` (13) — the two levels the review named. Each doc comment says what the level counts and that the 2026-09-10 measurement read it.
    - `retrievalTextFirstPlace` (1), which `bestRankOne` compares against. The rule carves 1 out, so this one is not a finding; the name makes the count read like the `retrievalTextTopPlaces` count beside it.
    - `meanBestRankPlacesAfterThePoint` (2), which was inside the `"%.2f"` format string. The rule reads no number in a string, so this one is not a finding either. The rendered mean does not change.

    The rule now reads 0 violations in the file.
  timestamp: 2026-09-10T22:21:52.747109+00:00
- actor: claude-code
  id: 01m26pkrqjtzejzqccckc1wskt
  text: |-
    ### implement — changed
    - evidence: 4 numbers now carry a name in `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/RetrievalTextSurfaceDiscoveryTests.swift`, the one file this step touched: `shippedAgentSurfaceTopPlaceLevel` (10) and `shippedHeldOutTopPlaceLevel` (13), which are the two findings of the review; and `retrievalTextFirstPlace` (1) and `meanBestRankPlacesAfterThePoint` (2), which the rule carves out but which had no name. `swiftlint` with the rule's own configuration (`only_rules: [no_magic_numbers]`, `allowed_numbers: [0, 1, -1, 100]`) read 2 violations over the file before the change and 0 after it. No test was deleted, no assertion was weakened, and no printed line changed. `swift test` at the root: 1,422 tests in 113 suites, all green, and no line holds `warning:` or `error:`. `swift build --package-path IntegrationTests`: clean, and `--build-tests` compiles the whole test target clean as well. I did not run the live measurement suite again, because this change gives names to numbers and changes no value the suite measures or reports; the numbers stand on this card from the 2026-09-10 run.
    - next: review. The two findings are now `- [x]` on the card. The card stays in doing.
  timestamp: 2026-09-10T22:22:01.970879+00:00
- actor: claude-code
  id: 01m26pnr95dy547tvbnzme8fvx
  text: |-
    ### commit — changed
    - evidence: 59493a4 fix(integration-tests): name the four numbers in the discovery test — 3 files changed
    - next: none. The task is ready for review.
  timestamp: 2026-09-10T22:23:07.045580+00:00
- actor: claude-code
  id: 01m26prexsg476p7gn8ff3tx2g
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` gives 0 findings over 1 file. The two findings of the section of 2026-09-10 18:11 are checked.
    - next: The card moves to done. No work stays open.
  timestamp: 2026-09-10T22:24:35.769931+00:00
- actor: claude-code
  id: 01m26ps21e38jr5wt7n4t5g8cq
  text: |-
    ### finish iteration 2 — clean

    - implement: changed, in one test file. Four numbers now carry a name. The linter read 2 violations before and reads 0 after. No test was deleted, no assertion is weaker, and no printed line changed. The live measurement suite was not run again, because a name change alters no measured value.
    - test: green. `swift test` gives 1422 pass in 113 suites, no warning. `swift build --package-path IntegrationTests` is clean, and the test target compiles.
    - commit: 59493a4, 3 files.
    - review: clean. 0 finding over `HEAD~1..HEAD`. Both prior findings are checked. The task moved to done.

    **The answer of this card, in one sentence.** Keep the full block for the keyword index and for the embedder. The held-out queries refute the guess that the embedder is the weak half: the split setting is the worst of the three on that group. The description-only setting reads a little better and costs half as much, but it cannot be taken here, because the same text gives the main session what it reads to write the call.
  timestamp: 2026-09-10T22:24:55.342165+00:00
position_column: done
position_ordinal: ffc080
title: Decide whether the retrieval index and the embedder read the full block or the description
---
## What happened

Card `^0z0te3n` made the selection prompt hold the description of each tool alone. It changed one half of the path. The other half was not examined.

The registry keeps two texts for each item, and it uses them for different work:

| text | what reads it | where |
|---|---|---|
| `renderBlock()`, the full block | BM25 and the trigram index | `MetadataIndex.swift:119-127` |
| `renderBlock()`, the full block | the embedder | `MetadataIndex+Embedding.swift:149` |
| `renderSummaryBlock()`, banner and description | the selection prompt | `MetadataIndex+SelectionCatalog.swift:16-18`, `SelectionTier.swift:453-455` |

So the model now selects from descriptions, and the retrieval tier still ranks and embeds the full JSDoc block, with every `@param` line and the `declare function` line in it.

This is not stated anywhere as a decision. It is what the default of the protocol gives when a consumer overrides one method and not the other.

## Why it deserves an answer

**For keyword ranking, the full block can be correct.** A query that names a parameter, for example "write a file with content", matches the `@param args.content` line. The description alone may not hold that word. Cutting the block could make BM25 worse.

**For the embedder, the full block is doubtful.** A vector of a description plus a TypeScript signature is not a vector of what the tool does. The signature words are the same across many tools: `args`, `Promise`, `declare function`, `string`. They pull every tool of the surface toward the same point, so the cosine scores separate the tools less. The description alone is the sentence a person would compare a task against.

**It is also the expensive half.** The embedder reads every block one time at the first search. Card `^zqz1zan` measured the blocks of one nine-entry surface at 17,263 characters, against 7,232 characters of description. So the embed cost is about twice what it must be, if the description is the correct text.

## What to do

1. Do not guess. Measure. Use the ten queries of `^zqz1zan` and the held-out set of card `^kn9ay20`, and compare three settings, with the selection tier switched off so only retrieval answers: the full block for both signals; the description for both; the full block for keyword and the description for the embedder.
2. Report for each setting where the correct tool ranks for each query.
3. Choose from the measurement, and write the choice and the numbers in the doc comment of `APISurface+SearchableMetadata.swift`.
4. If the registry gives no way to use one text for keyword and another for the embedder, do not build one here. Write a card in the registry repository and name it on this card.

## Rules

- Do not change what the selection prompt holds. Card `^0z0te3n` settled that, and this card is about the retrieval half.
- Do not edit a package checkout under `.build/checkouts`.
- A setting that is not measured is not a result.

## The answer

Measured by `RetrievalTextSurfaceDiscoveryTests` on 2026-09-10, and repeated to the digit. The choice is **the full block, for the keyword index and the embedder alike** — the shipped conformance, unchanged, and now a measured choice instead of a default. Giving the embedder the description alone is the worst of the three settings on the held-out group. The description-for-both setting reads a little better there, but `renderBlock()` also gives the main session the text it reads to write the call, so a consumer cannot take it. The registry card that would open that door is `^kh2ttmm`.

The per-query ranks of every setting, the totals, and the reasoning stand in the comments of this card, and in the doc comment of `APISurface+SearchableMetadata.swift`.

## Acceptance Criteria

- [x] The rank of the correct tool for each query, in each of the three settings, is on this card.
- [x] The choice is made and written in the doc comment of `APISurface+SearchableMetadata.swift`.
- [x] If the registry must change, a card exists there and this card names its short id. — `^kh2ttmm`, at `FoundationModelsMetadataRegistry/.kanban/tasks/01M26P0000R9VXQ7B3DKH2TTMM.md`.
- [x] The gated discovery suite passes after the change, with its counts on this card.

## Tests

- [x] `swift test` at the root: no failure, no warning. — 1,422 tests in 113 suites, all green.
- [x] `swift test --package-path IntegrationTests --no-parallel --filter AgentSurfaceDiscoveryTests`: passes. — 3 rounds, 19 correct paths and 3 undeclared in each.

#discovery #search-tools #metadata

## Review Findings (2026-09-10 18:11)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 2 file(s) reviewed, 8 not reviewed.

> 8 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 8 file(s)

- [x] `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/RetrievalTextSurfaceDiscoveryTests.swift:184` `code-hygiene/magic-numbers-swift` — Magic numbers should be replaced by named constants.
- [x] `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/RetrievalTextSurfaceDiscoveryTests.swift:185` `code-hygiene/magic-numbers-swift` — Magic numbers should be replaced by named constants.

The cause was corrected over the whole file, not on the two lines alone. Four numbers now carry a name: `shippedAgentSurfaceTopPlaceLevel`, `shippedHeldOutTopPlaceLevel`, `retrievalTextFirstPlace` and `meanBestRankPlacesAfterThePoint`. `swiftlint` with the rule's own configuration reads 0 violations in the file.

The live measurement suite was not run again. The change gives names to numbers; it changes no value, no assertion and no printed line, so the numbers this card records stand. `swift test` at the root and `swift build --package-path IntegrationTests --build-tests` are both clean.
