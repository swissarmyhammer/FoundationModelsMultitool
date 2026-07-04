---
depends_on:
- 01KWQC004XSC6ZS9PW10WF5GAD
position_column: todo
position_ordinal: '8280'
title: Conform APISurface.Entry to SearchableMetadata
---
## What
Make the rendered tool catalog searchable by the registry: conform `APISurface.Entry` to the registry's `SearchableMetadata` protocol.

- New file `Sources/FoundationModelsMultitool/Surface/APISurface+SearchableMetadata.swift`:
  - `extension APISurface.Entry: SearchableMetadata` with `public var id: String { path }` and `public func renderBlock() -> String { block }`.
  - `path` is the right id: it is the fully-qualified `tools.*` call path, unique per catalog (`MultiTool.Builder.build()` validates name collisions), and it is exactly what the selection grammar's id enum and `findAPIs` feedback need to name.
  - `block` (the `// tools.<path>` banner + verbatim `descriptor.source`) is the search surface — the same text `Librarian.assemblePrefix` uses today.
  - Rely on the protocol's default `renderSummaryBlock()` (identical to `renderBlock()`); descriptor blocks are already compact.

## Acceptance Criteria
- [ ] `APISurface.Entry` satisfies `SearchableMetadata`; `entry.id == entry.path` and `entry.renderBlock() == entry.block` hold for grouped and standalone entries.
- [ ] A `MetadataSearcher(items: surface.entries, mode: .retrieval)` over a real built registry surface ranks the expected tool first for a keyword query.
- [ ] `swift build` and full `swift test` green.

## Tests
- [ ] New `Tests/FoundationModelsMultitoolTests/APISurfaceSearchableMetadataTests.swift`: id/renderBlock identity assertions for a standalone and a grouped entry; a `.retrieval` search over a `MultiTool.Builder`-built surface (reuse existing tool fixtures) returns the expected `path` as the top match.
- [ ] `swift test` — full suite green.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.