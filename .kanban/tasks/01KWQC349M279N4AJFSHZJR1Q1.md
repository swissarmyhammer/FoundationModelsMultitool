---
depends_on:
- 01KWQC25DQYWTVRA16TKYPWKCW
position_column: todo
position_ordinal: '8780'
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