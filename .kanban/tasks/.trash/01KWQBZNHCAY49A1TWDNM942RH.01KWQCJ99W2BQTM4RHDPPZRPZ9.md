---
position_column: todo
position_ordinal: '80'
title: Make FoundationModelsMetadataRegistry consumable by remote URL
---
## What
Work in the sibling repo `../FoundationModelsMetadataRegistry` (not this repo). Its `Package.swift` declares FoundationModelsRouter as a local path dependency (`.package(path: "../FoundationModelsRouter")`), which makes the package unconsumable as a remote URL dependency — a remotely-fetched package cannot resolve local path deps. FoundationModelsMultitool will consume the registry by URL (same pattern it already uses for Router), so this must change first.

- Edit `../FoundationModelsMetadataRegistry/Package.swift`: replace `.package(path: "../\(routerDependencyName)")` with `.package(url: "https://github.com/swissarmyhammer/\(routerDependencyName)", branch: "main")` — mirroring `../FoundationModelsMultitool/Package.swift`'s existing Router declaration exactly.
- Update the `routerDependencyName` doc comment (it currently explains the sibling-path convention).
- Verify the registry still builds and its full test suite passes.
- Commit and push to `origin/main` — Multitool's CI resolves the registry remotely, so an unpushed change is invisible to it.

## Acceptance Criteria
- [ ] `../FoundationModelsMetadataRegistry/Package.swift` contains no `.package(path:)` dependencies.
- [ ] `swift build` and `swift test` succeed in `../FoundationModelsMetadataRegistry`.
- [ ] The change is committed and pushed to `origin/main` of FoundationModelsMetadataRegistry.

## Tests
- [ ] Run `swift test` in `../FoundationModelsMetadataRegistry` — full suite green (no new tests needed; this is a manifest-only change verified by the existing suite).
- [ ] `swift package resolve` in `../FoundationModelsMetadataRegistry` succeeds and `Package.resolved` pins Router by URL.

## Workflow
- Use `/tdd` where applicable — this task is manifest-only; the registry's existing suite is the regression net.