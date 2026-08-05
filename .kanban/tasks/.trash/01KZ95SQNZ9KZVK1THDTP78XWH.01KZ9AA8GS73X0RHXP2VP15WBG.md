---
assignees:
- claude-code
position_column: todo
position_ordinal: '9280'
title: '[Shelltool] Bump platform floor to macOS 27 to consume the Operations Router-vocabulary shim'
---
Discovered while implementing ^pzsgvde ([OperationTool] Operations shim: typealias the vocabulary to Router, keep EventEmittingTool local).

## Context

`../FoundationModelsOperationTool`'s `Operations` target now depends on `FoundationModelsRouter` (git@github.com:swissarmyhammer/FoundationModelsRouter.git, branch main) to re-export its vocabulary (`OperationEvent`, `OperationOutcome`, `OperationEventSink`, `ForkableTool`) as typealiases. Router's `Package.swift` declares `platforms: [.macOS("27.0")]`, so SwiftPM requires every target that links it — transitively including `Operations` — to declare at least macOS 27. `FoundationModelsOperationTool/Package.swift` was bumped from `.macOS(.v26)` to `.macOS("27.0")` (string literal, not the `.v27` enum case, to stay on swift-tools-version 6.2 — same pattern as `FoundationModelsMCP` and `FoundationModelsFileTool`).

`../FoundationModelsShelltool/Package.swift` still declares `platforms: [.macOS(.v26)]` and depends on `FoundationModelsOperationTool` (git branch main) for the `Operations`/`OperationsCLI` products. Once ^pzsgvde's change lands on `FoundationModelsOperationTool`'s `main` branch, `swift package update && swift build` in `FoundationModelsShelltool` fails:

```
error: The package product 'Operations-product' requires minimum platform version 27.0 for the macOS platform, but this target supports 26.0
error: The package product 'OperationsCLI-product' requires minimum platform version 27.0 for the macOS platform, but this target supports 26.0
```

Verified locally via `swift package edit FoundationModelsOperationTool --path ../FoundationModelsOperationTool` (then `swift package unedit` to restore Shelltool's clean state — no Shelltool files were left modified).

This mirrors the already-known, deferred cascade noted in `FoundationModelsACPAgent/Package.swift`'s comment ("Router's floor is macOS 27 / FoundationModels v2; `.v26` here mirrors the sibling manifests pending a tools-version bump — see FoundationModelsExtras/Package.swift") and in `FoundationModelsExtras/Package.swift`.

## What

- `../FoundationModelsShelltool/Package.swift`: bump `platforms: [.macOS(.v26)]` to `platforms: [.macOS("27.0")]` (string literal — Shelltool stays on swift-tools-version 6.2, matching the family convention).
- Confirm no iOS platform entry needs touching (Shelltool already declares macOS-only, per its own comment about `Subprocess`/`/bin/sh -c`).

## Acceptance Criteria

- [ ] `cd ../FoundationModelsShelltool && swift package update && swift build && swift test` green, once ^pzsgvde's `FoundationModelsOperationTool` change is on `main`.

## Note

This task is a prerequisite for acceptance criterion 4 of ^pzsgvde ("A downstream sibling builds against the shim"), which could not be verified end-to-end within ^pzsgvde's scope (that task's explicit instruction pins the edit to `FoundationModelsOperationTool` only). #phase-1