---
comments:
- actor: wballard
  id: 01kwfx69mk05e3sjvta5mv0m6s
  text: |-
    TDD scaffold complete and verified locally:

    - RED: wrote Tests/FoundationModelsMultitoolTests/ScaffoldTests.swift first; `swift test` failed with "Could not find Package.swift" (package didn't exist yet) — expected failure reason.
    - GREEN: added Package.swift (swift-tools-version 6.1, platforms [.macOS("27.0")], library target FoundationModelsMultitool, test target FoundationModelsMultitoolTests, dependency on https://github.com/swissarmyhammer/FoundationModelsRouter branch main, product FoundationModelsRouter), Sources/FoundationModelsMultitool/FoundationModelsMultitool.swift placeholder, then a clean `rm -rf .build && swift build --build-tests` succeeded (only warnings are from the third-party mlx-swift C++ Metal shader code, none from our own files) and `swift test` passed: "Test run with 1 test in 1 suite passed", 0 failures. Re-ran multiple times including after a full clean rebuild — consistently green.
    - .gitignore already had .build/ and .swiftpm/ from repo init; left untouched.
    - Added .github/workflows/ci.yml mirroring ../FoundationModelsRouter/.github/workflows/ci.yml: calls the org's reusable `swissarmyhammer/workflows/.github/workflows/swift-ci.yaml@main` (fetched and inspected — runs on [self-hosted, macOS], does `swift build --build-tests` + `swift test`) under a `unit:` job with push/pull_request/workflow_dispatch triggers. Validated YAML syntax.
    - Package.resolved generated and NOT gitignored (confirmed against .gitignore).
    - Dispatched double-check adversarial review agent before handoff (network + build access confirmed available in this sandbox).

    Nothing left uncommitted intentionally — per /implement process, commit happens in the later pipeline stage (commit/review), not here.
  timestamp: 2026-07-01T22:35:59.507439+00:00
position_column: doing
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
- [x] `swift build` succeeds on macOS 27 SDK
- [x] `swift test` runs (empty-but-green suite)
- [x] The test target can `import FoundationModelsMultitool`, `import FoundationModelsRouter`, `import FoundationModels`, `import JavaScriptCore`
- [x] CI workflow runs build + test

## Tests
- [x] `Tests/FoundationModelsMultitoolTests/ScaffoldTests.swift` — a Swift Testing `@Test` that imports all four modules and asserts a trivial truth (compilation is the assertion)
- [x] `swift test` → passes

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.