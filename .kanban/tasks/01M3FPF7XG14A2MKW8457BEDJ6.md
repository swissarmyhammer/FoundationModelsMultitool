---
assignees:
- claude-code
depends_on:
- 01M3FMSTTSP16K9AE7JKZAEFGZ
position_column: todo
position_ordinal: '8e80'
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
- Use `/tdd`. Write failing tests first, then do the implementation that makes them pass.