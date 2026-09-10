---
assignees:
- claude-code
position_column: todo
position_ordinal: '8580'
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

## Acceptance Criteria

- [ ] The rank of the correct tool for each query, in each of the three settings, is on this card.
- [ ] The choice is made and written in the doc comment of `APISurface+SearchableMetadata.swift`.
- [ ] If the registry must change, a card exists there and this card names its short id.
- [ ] The gated discovery suite passes after the change, with its counts on this card.

## Tests

- [ ] `swift test` at the root: no failure, no warning.
- [ ] `swift test --package-path IntegrationTests --no-parallel --filter AgentSurfaceDiscoveryTests`: passes.

#discovery #search-tools #metadata