---
comments:
- actor: wballard
  id: 01kwqd22jgsb41hnkjbwpnnwz8
  text: |-
    Implemented via TDD:
    - Added `Tests/FoundationModelsMultitoolTests/MetadataRegistrySmokeTests.swift` first (imports `FoundationModelsMetadataRegistry`, defines a trivial `GitCommand: SearchableMetadata` fixture mirroring the registry README's git-commands example, builds `MetadataSearcher(items:, mode: .retrieval)`, asserts `commit` ranks first for "commit changes to git"). Confirmed RED: `swift test --filter MetadataRegistrySmokeTests` failed with "unable to resolve module dependency: 'FoundationModelsMetadataRegistry'".
    - Added `metadataRegistryDependencyName = "FoundationModelsMetadataRegistry"` constant to `Package.swift` alongside `routerDependencyName`, added the `.package(url: "https://github.com/swissarmyhammer/FoundationModelsMetadataRegistry", branch: "main")` dependency, and linked the `FoundationModelsMetadataRegistry` product into the `FoundationModelsMultitool` library target, `FoundationModelsMultitoolTests`, and `FoundationModelsMultitoolIntegrationTests`.
    - Confirmed GREEN: `swift package resolve` pins it in `Package.resolved` (branch main, revision 4e49de8); `swift build` succeeds; `swift test --filter MetadataRegistrySmokeTests` passes.

    Discovery (unrelated to this task): full `swift test` has one pre-existing failure — `HardeningTests.readmeInjectedGlobalsListMatchesRuntime` — because commit e366c62 (README rewrite) moved the `### Injected globals` section out of `README.md` into `docs/SECURITY.md`, breaking that machine-checked sync test. Confirmed via `git stash -u` that this failure exists on `main` with none of this task's changes applied, so it's not a regression from this task. Filed as a new kanban task 1pn8764 ("Fix HardeningTests README/SECURITY.md drift") rather than fixing in scope here.
  timestamp: 2026-07-04T20:27:59.440598+00:00
depends_on: []
position_column: done
position_ordinal: '9580'
title: Add FoundationModelsMetadataRegistry dependency to Package.swift
---
## What
Add the metadata registry as a remote dependency of this package, following the manifest's existing conventions (named constants, doc comments explaining why each target links what).

Note: the registry is already consumable by URL — `../FoundationModelsMetadataRegistry/Package.swift` already declares its Router dependency as `.package(url: "https://github.com/swissarmyhammer/FoundationModelsRouter", branch: "main")` and `main` is in sync with `origin/main`. No registry-side change is needed; this task verifies remote resolution works as part of its build.

In `Package.swift`:
- Add a `metadataRegistryDependencyName = "FoundationModelsMetadataRegistry"` constant alongside `routerDependencyName`.
- Add `.package(url: "https://github.com/swissarmyhammer/FoundationModelsMetadataRegistry", branch: "main")` to `dependencies`.
- Add the registry product to the `FoundationModelsMultitool` library target, the `FoundationModelsMultitoolTests` unit test target, and the `FoundationModelsMultitoolIntegrationTests` target (later tasks import it from all three).

Add a smoke test proving the dependency actually links and works: in `Tests/FoundationModelsMultitoolTests/`, a small test that defines a trivial `SearchableMetadata` fixture, builds a `MetadataSearcher(items:, mode: .retrieval)`, and asserts a keyword query ranks the right item first (mirrors the registry README's git-commands example).

## Acceptance Criteria
- [x] `swift package resolve` succeeds and `Package.resolved` pins FoundationModelsMetadataRegistry by URL.
- [x] `swift build` succeeds; `import FoundationModelsMetadataRegistry` compiles in the unit test target.
- [x] Full `swift test` remains green.

## Tests
- [x] New `Tests/FoundationModelsMultitoolTests/MetadataRegistrySmokeTests.swift`: `.retrieval` search over a 3–5 item fixture catalog returns the expected id first.
- [x] `swift test` — full suite green.

## Workflow
- Use `/tdd` — write the failing smoke test first (it fails to compile without the dependency), then add the dependency to make it pass.

## Implementation note (2026-07-04)
Full `swift test` has one pre-existing, unrelated failure — `HardeningTests.readmeInjectedGlobalsListMatchesRuntime` — caused by an earlier commit (e366c62, README rewrite) that moved the `### Injected globals` section into `docs/SECURITY.md`. Confirmed via `git stash -u` (both by this task's implementer and independently by the adversarial double-check reviewer) that this failure pre-exists on `main` without this task's changes. Filed as a separate kanban task (short_id `1pn8764`) rather than fixed here, since it is out of scope for a Package.swift dependency-wiring task. `swift test --filter MetadataRegistrySmokeTests` (this task's own new test) passes cleanly, and `swift build`/`swift package resolve` are green.