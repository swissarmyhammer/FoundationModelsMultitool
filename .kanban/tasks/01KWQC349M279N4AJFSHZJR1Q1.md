---
comments:
- actor: wballard
  id: 01kwqsby5yz699330ntampkrpe
  text: |-
    Implemented the docs sweep. Findings during research:

    - README.md has zero librarian/findAPI/FoundAPI mentions already (it was rewritten as a minimal library landing page in commit e366c62, with no discovery-internals prose at all) — nothing to change there, and the "README's discovery section names FoundationModelsMetadataRegistry" acceptance bullet is moot since there is no discovery section in the current README.
    - Package.swift, Interpreter/*, Surface/APISurface.swift, Surface/ToolDescriptor.swift, Surface/MultiToolBuilder.swift, MultiTool.swift, and docs/SECURITY.md were checked per the task's explicit file list. Interpreter/* had no stale mentions. The other files had stale "the librarian prefix"/"librarian's instruction prefix" doc-comment phrasing implying the deleted `Librarian` type still backs the instruction prefix — updated each to reference the registry-backed selection tier (FoundationModelsMetadataRegistry's MetadataSearcher/SelectionTier) while preserving verbatim plan.md quotations as historical citations.
    - Left untouched (out of scope, already accurate): FindAPITool.swift and MultiToolAgent.swift/TranscriptAnalyzer.swift's "former `Librarian`"/"former `FoundAPIs`" phrasing (already past-tense/historical, fixed by a prior task) and the live `librarian:` parameter name in MultiToolAgent.swift/CLIRunner.swift (a real identifier naming the surviving conceptual role, not a reference to the deleted type — renaming it would be a code change outside this comment-only docs task).

    Verification: `swift build` exit 0; `swift test` — 250/250 unit tests pass, 11 gated integration tests correctly skipped (MULTITOOL_INTEGRATION unset). `grep -rn "Librarian" Sources/ README.md` now only matches accurate historical "former `Librarian`" prose. Diff is comment/prose only across Package.swift, MultiTool.swift, Surface/APISurface.swift, Surface/MultiToolBuilder.swift, Surface/ToolDescriptor.swift, docs/SECURITY.md.

    Adversarial double-check agent spawned to verify before handoff.
  timestamp: 2026-07-05T00:03:05.534518+00:00
- actor: wballard
  id: 01kwqsh0h6dnyq22m6svy000j8
  text: |-
    Adversarial double-check PASS, no findings — confirmed each doc edit correctly redirects from the deleted Librarian type to the registry-backed selection tier, remaining lowercase "librarian" occurrences are plan.md citations, README correctly left untouched (no discovery content to sweep), swift build/test both green (250/250 unit tests, gated suite skipped as expected), and scope matches exactly (no overreach/underreach).

    Leaving task in `doing` per /implement — ready for /review.
  timestamp: 2026-07-05T00:05:51.782316+00:00
depends_on:
- 01KWQC25DQYWTVRA16TKYPWKCW
position_column: doing
position_ordinal: '8180'
title: 'Docs sweep: point librarian references at the registry'
---
## What
Sweep prose so it matches the migrated architecture — the "librarian" *role* survives (a flash-slot model selecting APIs), but its implementation now lives in FoundationModelsMetadataRegistry.

- `README.md`: update any description of findAPIs/discovery internals (guided `FoundAPIs`, lexical pre-filter) to say selection is backed by FoundationModelsMetadataRegistry's `.selection` tier (id-enum grammar, verbatim blocks), with a link to that package.
- `Package.swift`: doc comments for the new registry dependency constant are in place (from the earlier dependency task); re-check remaining comments for stale `Librarian` mentions.
- Source doc comments that name the deleted types: `Sources/FoundationModelsMultitool/Surface/APISurface.swift` ("backs the librarian prefix"), `Surface/ToolDescriptor.swift` ("the librarian's instruction prefix"), `Surface/MultiToolBuilder.swift`, `MultiTool.swift`, `Interpreter/*` if any — update to reference the registry-backed selection tier where they explain the discovery path.
- Do NOT rewrite `plan.md` history — it is the historical design record; leave it as-is.

## Acceptance Criteria
- [ ] `grep -rn "Librarian" Sources/ README.md` yields only prose that accurately describes the registry-backed selection tier (no references to deleted local types as if they still exist).
- [ ] README's discovery section names FoundationModelsMetadataRegistry.
- [ ] `swift build` and full `swift test` green (comment-only changes; suite is the regression net).

## Tests
- [ ] `swift test` — full suite green.
- [ ] Automated grep check (run as part of the task): `grep -rn "FoundAPI\|Agent/Librarian" Sources/` returns nothing.

## Workflow
- Use `/tdd` where applicable — this is a docs task; the build and grep checks are the verification.