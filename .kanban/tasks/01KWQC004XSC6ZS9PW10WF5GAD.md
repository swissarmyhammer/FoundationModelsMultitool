---
depends_on: []
position_column: todo
position_ordinal: '8180'
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
- [ ] `swift package resolve` succeeds and `Package.resolved` pins FoundationModelsMetadataRegistry by URL.
- [ ] `swift build` succeeds; `import FoundationModelsMetadataRegistry` compiles in the unit test target.
- [ ] Full `swift test` remains green.

## Tests
- [ ] New `Tests/FoundationModelsMultitoolTests/MetadataRegistrySmokeTests.swift`: `.retrieval` search over a 3–5 item fixture catalog returns the expected id first.
- [ ] `swift test` — full suite green.

## Workflow
- Use `/tdd` — write the failing smoke test first (it fails to compile without the dependency), then add the dependency to make it pass.