---
assignees:
- claude-code
position_column: todo
position_ordinal: '8980'
title: Cap SelectionTier.idEnumGrammar ids array with maxItems to stop runaway generation (port of registry fix 98a91db)
---
## What

Port `FoundationModelsMetadataRegistry` commit `98a91db` ("fix(selection): cap idEnumGrammar ids array with maxItems to stop runaway generation") to this package's own copy of the selection grammar builder.

When the selection code was extracted from the registry into `FoundationModelsRanker`, the copy came over WITHOUT the `maxItems` cap: `Sources/FoundationModelsRanker/Selection/SelectionTier.swift`'s `idEnumGrammar(ids:)` (around line 303) injects `enum` + `uniqueItems: true` into the `ids` array schema but never sets `maxItems`. The xgrammar pipeline (via Router's `RuntimeJSONSchemaConverter` → `DynamicGenerationSchema(maximumElements:)` → Apple `GenerationSchema` Codable → xgrammar `json_schema_converter.cc`) enforces `minItems`/`maxItems` but silently ignores `uniqueItems`, so the compiled grammar permits an unbounded-length array of repeated enum members.

Empirically confirmed 2026-07-14 on real hardware (M3 Ultra, Qwen2.5-1.5B-Instruct-4bit, via FoundationModelsMultitool's gated `PrefixReuseTests`): an off-topic selection intent deterministically produced a ~6150-token repeated-id runaway (~190-195s wall clock); adding `maxItems = ids.count` to the effective grammar bounded it to ~2.5s. `grep -rn maxItems Sources/` in this repo returns nothing — the whole package lacks the cap.

## Fix

In `idEnumGrammar(ids:)`, set `maxItems` on the `ids` array subschema to `ids.count`, mirroring the registry's fixed copy verbatim (a selection can never legitimately contain more ids than there are candidates).

## Acceptance Criteria

- [ ] `SelectionTier.idEnumGrammar(ids:)`'s emitted JSON schema contains `"maxItems": <ids.count>` on the `ids` array.
- [ ] A unit test asserts the cap equals the candidate count (mirror the registry's `SelectionTests` addition from 98a91db).
- [ ] Full `swift test` remains green.
