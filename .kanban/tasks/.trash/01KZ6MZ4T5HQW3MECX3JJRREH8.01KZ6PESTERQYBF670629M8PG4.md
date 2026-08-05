---
assignees:
- claude-code
depends_on: []
position_column: todo
position_ordinal: '8280'
title: '[OperationTool] Operations shim: typealiases re-exporting Router'
---
Repo: ../FoundationModelsOperationTool. Basis: eventplan.md §"Phases" phase 1 — "the siblings continue to compile through a transitional shim." The shim dies with OperationTool in phase 5.

## What
Reverse the dependency edge (sequencing avoids the SwiftPM cycle: the previous task already removed Router's dependency on this package and pushed Router `main`).

- `Package.swift`: add `.package(url: "git@github.com:swissarmyhammer/FoundationModelsRouter.git", branch: "main")` and `.product(name: "FoundationModelsRouter", package: "FoundationModelsRouter")` to the `Operations` target. This pulls MLX transitively into the doomed packages' builds — accepted, temporary build weight per the plan.
- Replace the bodies of the five moved files (`OperationEvent.swift`, `OperationOutcome.swift`, `OperationEventSink.swift`, `EventEmittingTool.swift`, `ForkableTool.swift`) in `Sources/Operations/` with documented public typealiases re-exporting Router's canonical types (e.g. `public typealias OperationEvent = FoundationModelsRouter.OperationEvent`), so a build holding both imports sees one type, not two ambiguous types. Each typealias needs a `///` doc comment — `Tests/OperationsTests/DocCoverageTests.swift:18-22` polices every public decl.
- `EventEmittingContext.swift`, `ForkableContext.swift`, and `OperationTool.swift`'s conditional conformance (`extension OperationTool: EventEmittingTool where Context: EventEmittingContext`, OperationTool.swift:218-234) stay as-is and must compile against the typealiases.
- The vocabulary behavior tests (`OperationOutcomeTests.swift`, `EventEmittingToolTests.swift`) were ported to Router; keep them here too if they still pass against the typealiases (they should — same types), or thin them to shim-compile checks. Prefer keeping: they prove the shim is transparent.

## Acceptance Criteria
- [ ] `cd ../FoundationModelsOperationTool && swift build && swift test` green (including DocCoverageTests and the NotesTool example targets)
- [ ] The five files contain only typealiases + docs; no duplicate type definitions remain
- [ ] `OperationTool`'s conditional `EventEmittingTool` conformance compiles unchanged
- [ ] A downstream sibling builds against the shim: `cd ../FoundationModelsShelltool && swift build` succeeds after `swift package update` (Shelltool is the heaviest vocabulary user)

## Tests
- [ ] Existing `OperationsTests` suite green against the typealiases (codable round trips, `.other` decoder, connecting semantics — now exercising Router's canonical types through the shim)
- [ ] `cd ../FoundationModelsOperationTool && swift test` passes

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #phase-1 #router-first