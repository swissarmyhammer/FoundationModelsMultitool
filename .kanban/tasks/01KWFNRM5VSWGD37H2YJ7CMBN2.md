---
position_column: todo
position_ordinal: '80'
title: 'M0: Scaffold SwiftPM package with Router dependency'
---
## What
Create the package skeleton per plan.md M0:
- `Package.swift` — `swift-tools-version: 6.1`, `platforms: [.macOS("27.0")]` (OS-27 floor, no `@available` branching), library target `FoundationModelsMultitool`, test target `FoundationModelsMultitoolTests`.
- Dependencies: `FoundationModels` + `JavaScriptCore` (system frameworks, just `import`), and the package `.package(url: "https://github.com/swissarmyhammer/FoundationModelsRouter", branch: "main")` with product `.product(name: "FoundationModelsRouter", package: "FoundationModelsRouter")`. Commit `Package.resolved`.
- `Sources/FoundationModelsMultitool/` with a placeholder module file so the target builds.
- `.github/workflows/ci.yml` — macOS runner with the OS-27 SDK, `swift build` + `swift test` (mirror ../FoundationModelsRouter/.github as the template).
- `.gitignore` for `.build/`, `.swiftpm/`.

## Acceptance Criteria
- [ ] `swift build` succeeds on macOS 27 SDK
- [ ] `swift test` runs (empty-but-green suite)
- [ ] The test target can `import FoundationModelsMultitool`, `import FoundationModelsRouter`, `import FoundationModels`, `import JavaScriptCore`
- [ ] CI workflow runs build + test

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/ScaffoldTests.swift` — a Swift Testing `@Test` that imports all four modules and asserts a trivial truth (compilation is the assertion)
- [ ] `swift test` → passes

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.