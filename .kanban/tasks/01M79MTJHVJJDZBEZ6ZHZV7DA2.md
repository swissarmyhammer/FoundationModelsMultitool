---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: SearchIndexCache keeps no embedder alive, and gives a public test seam
---
## What
Request from foundationmodelsacpagent-ec (ACPAgent card ^wpsm1jx) and testudoapp-75, after card ^d84hmxw. The embed slots of `SearchIndexCache` held the embedder strongly. An embedder holds a model, so the models of old sessions and old profiles stayed loaded until 8 newer slots pushed them out. The process-wide cache also made tests depend on other tests.

- Sources/FoundationModelsMultitool/Discovery/SearchIndexCache.swift: each embed slot holds only weak references (`WeakReference`) to the owner, to the embedder and to the `SharedCatalogEmbedding`. The searchers of each session keep the shared embed. When the last session ends, the slot is empty, and the cache drops it. No capacity for embed slots.
- `IdentifiedEmbedding` now gives `embeddingOwner: any AnyObject & Sendable` in place of `embeddingIdentity: ObjectIdentifier`. A released owner never matches a new object. No sibling used the old member.
- Public test seam: `SearchIndexCache` (public `init(capacity:)`, `builds`, `sharedEmbeddings`, `liveSharedEmbeddings`) and `Registry.makeSessionToolsAndStaging(selection:embedder:sampleModel:indexCache:)`.

## Acceptance Criteria
- [x] After the sessions end, the cache keeps no embedder, no owner and no shared embed.
- [x] Two open sessions with the same embedder owner share one embed.
- [x] A session after the last session ended makes a new embed.
- [x] A test can give its own cache to `makeSessionToolsAndStaging`.

## Tests
- [x] Tests/FoundationModelsMultitoolTests/DiscoveryEmbedderTests.swift: new tests, and the sharing tests keep the first session open.
- [x] `swift test` passes.

## Workflow
- Use `/tdd`. #step1
## Review Findings (2026-11-12 23:07)

- [x] `Sources/FoundationModelsMultitool/Discovery/SearchIndexCache.swift:326` `code-hygiene/disallowed-constructs-swift` — no_unchecked_sendable: Instead of @unchecked Sendable, write a plain Sendable conformance or a @preconcurrency import. Fixed: `WeakReference<Object: AnyObject & Sendable>: Sendable` with `weak let`. Only an `IdentifiedEmbedding` embedder now shares its embed between sessions; another embedder shares it only inside one bundle.
