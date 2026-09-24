---
assignees:
- claude-code
depends_on:
- 01M3A3DF9G5AFQ8R2EQ46NR78V
position_column: todo
position_ordinal: 8a80
title: 'Web: mount WebCapability in code mode with withWeb'
---
## What
Mount the web verbs in code mode, the same way as `files`. Design: `web.md` § "Configuration" (the builder short form) and § "Mount in code mode". Decision 5: `withWeb()` defaults to `.fromEnvironment()`.

- `Sources/FoundationModelsMultitool/Capabilities/Web/WebCapability.swift`: `public struct WebCapability: Capability` with `noun = "web"` and `tools = [Search(context:), Fetch(context:)]` over one `WebContext`, modelled on `Capabilities/Files/FilesCapability.swift`. Public init `init(configuration: WebConfiguration = .fromEnvironment(), sessionConfiguration: URLSessionConfiguration = .ephemeral)`.
- `Sources/FoundationModelsMultitool/Surface/MultiToolBuilder.swift`: add `withWeb(configuration: WebConfiguration = .fromEnvironment(), sessionConfiguration: URLSessionConfiguration = .ephemeral) -> Self` beside `withFiles` (`:285`), with a doc comment in the style of `withFiles`. It does not throw.

## Acceptance Criteria
- [ ] `withWeb` renders exactly `tools.web.search` and `tools.web.fetch`; a builder with no `withWeb` renders no `web` entry.
- [ ] A second `withWeb`, or an MCP server named `web`, is `.duplicateNoun` at `buildRegistry()`.
- [ ] `searchTools`, `help()`, and `docs()` find both verbs.
- [ ] Both verbs answer inline (no background mount), the same as the files verbs.

## Tests
- [ ] Create `Tests/FoundationModelsMultitoolTests/WebCapabilityTests.swift`, modelled on `FilesCapabilityTests.swift`: noun, exactly two verbs, one shared context, render, no entries without `withWeb`, `.duplicateNoun`, `searchTools`, `help()`, `docs()`, inline mount.
- [ ] Run `swift test --filter WebCapabilityTests`. All pass. Then run `swift test`.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #web