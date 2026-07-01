---
depends_on:
- 01KWFNSGV7FZFCC1HQ5V2CCAQX
position_column: todo
position_ordinal: '8580'
title: 'M2.5: Builder + APISurface — model-agnostic tool catalog'
---
## What
Per plan.md "Adding tools is the easy path" + Component 2/7:
- `Sources/FoundationModelsMultitool/Surface/MultiToolBuilder.swift` — `MultiTool.Builder` with `addTool(_:)` (generic over `T: Tool`, capturing the concrete type for later existential opening), `addTools(_:)`, `addGroup(named:_:)`, `build()`. Pure catalog — NO model wiring.
- `Sources/FoundationModelsMultitool/Surface/APISurface.swift` — the rendered catalog (list of `ToolDescriptor` + group structure): backs the librarian prefix, `help()`/`docs()`, and a host-listable data view.
- Namespacing per plan Resolved #5: standalone tools flat at `tools.<name>`; grouped under `tools.<group>.<name>`; duplicate flat names → `build()` throws (fail loud), duplicates across groups are fine.
- Completeness contract: `build()` throws if any tool fails ToolAPIRenderer's full rendering.

## Acceptance Criteria
- [ ] Builder with fixture tools produces an `APISurface` whose concatenated declaration blocks match a golden file
- [ ] Two flat tools with the same `name` → `build()` throws naming the collision
- [ ] `addGroup(named: "github", …)` renders `tools.github.<name>` declarations
- [ ] A tool that can't be fully rendered → `build()` throws (no lossy stub)

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/BuilderSurfaceTests.swift` — golden surface for a fixture set, collision error, group namespacing, completeness failure
- [ ] `swift test --filter BuilderSurfaceTests` → passes

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.