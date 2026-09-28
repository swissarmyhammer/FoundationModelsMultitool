---
assignees:
- claude-code
position_column: todo
position_ordinal: '8980'
title: 'Measure the retrieval-text choice again: the 2026-09-10 table was measured with the Router padding defect'
---
## What
The doc comment on `extension APISurface.Entry: SearchableMetadata` (`Sources/FoundationModelsMultitool/Surface/APISurface+SearchableMetadata.swift`) records a table from 2026-09-10 and chooses the full block for BM25 and for the embedder. Router task ^nmmnn7k (FoundationModelsRouter 2a79f92) found that the batch embed pooled a pad token for every row but the longest. Thus the cosine half of that table measured a padding artifact.

`RetrievalTextSurfaceDiscoveryTests` on 2026-09-28 (Router 2a79f92, card ^hd8266a) printed:
- block/block: agentSurface rank 1 9/10, top 3 10/10, mean 1.10; heldOut rank 1 9/15, top 3 14/15, mean 1.87.
- block/description: agentSurface 10/10, 10/10, 1.00; heldOut 11/15, 14/15, 1.67.
- description/description: agentSurface 9/10, 10/10, 1.10; heldOut 11/15, 14/15, 1.60.

The doc says block/description is the worst setting on heldOut (6/15). That is not true now.

## Acceptance Criteria
- [ ] Run `RetrievalTextSurfaceDiscoveryTests` again (2 runs) and replace the table with the new figures.
- [ ] Decide the retrieval text again from the new figures, and write the reason in the doc comment.

## Tests
- [ ] `swift test --package-path IntegrationTests --no-parallel --filter RetrievalTextSurfaceDiscoveryTests` passes.