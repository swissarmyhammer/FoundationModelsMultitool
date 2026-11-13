---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: Build the tool search index one time and share it between sessions
---
## What
Request from testudoapp-75 (TestudoApp card ^qa2eddw). `sample` showed that each ACPAgent `session/new` builds the search index of the catalog two times: `MultiTool.RegistryBundle.init` for the hint searcher and `SearchToolsTool.makeSearcher` for the discovery searcher. That is about 0.4 s of CPU for each session.

- New Sources/FoundationModelsMultitool/Discovery/SearchIndexCache.swift: a process-wide cache (`SearchIndexCache.shared`) of `MetadataIndex` values, keyed by the catalog entries. It keeps the 8 catalogs used last. The build runs under the lock.
- `RegistryBundleShape` gets `indexCache`. `RegistryBundle.init` gets the index one time and gives it to both searchers.
- New `SearchToolsTool.makeSearcher(over index:selection:embedder:)`. The entries form uses the shared cache.
- New internal `Registry.makeSessionToolsAndStaging(selection:embedder:sampleModel:indexCache:)`. The public form uses `.shared`.

## Acceptance Criteria
- [x] One session builds its index one time.
- [x] Two sessions with the same tool set build the index one time, and both search.
- [x] A different tool set builds its own index. The cache keeps only the catalogs used last.

## Tests
- [x] New Tests/FoundationModelsMultitoolTests/SearchIndexCacheTests.swift.
- [x] `swift test` passes.

## Workflow
- Use `/tdd`. #step1