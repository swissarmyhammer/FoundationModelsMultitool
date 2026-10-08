---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4esw6fvvq038zx62scd81v2
  text: |-
    Research and implementation notes:
    - Decision: an optional result field renders as `name: T | null` (not `name?: T | null`). `ArgumentMarshaler.renderOutput(_:)` always writes the key with `null` at each level of nested objects and arrays, so the key is never missing. The surface already uses this form in `MultiTool+SandboxGlobals.swift` (`latestProgress: string | null`).
    - `ToolAPIRenderer.declaredType(of:on:)` and `declaredType(ofObject:on:)` now take an internal `DeclaredSide` (`.argument` default, `.result`). A new private `declaredMember(for:on:)` writes one member. `render(name:description:arguments:returns:onWiden:)` declares `Promise<result.shape.declaredResultType>`.
    - New public `ToolValueShape.declaredResultType`. `ToolValueShape.declaredType` stays the argument form on purpose: `TypedMockDryRun` uses `declaredType` as the hidden type tag of a mock result, and compares it with the tag of an argument shape when a snippet passes one result into another tool. A result-form tag would break that chained-call identity, so the dry run is not changed.
    - Goldens: no golden surface file has an optional result field, so no golden changed. The `args` type is unchanged everywhere.
    - Fixture names: `SampleSnippetFixtures.swift` already has `ForecastTool`, so the new fixture is `OutlookTool` / `OutlookResult` / `OutlookDay`.
    - `swift build --build-tests` prints one SwiftPM build-system line, `warning: missing creator for mutated node: (.../mlx-swift_Cmlx.bundle/Contents/MacOS)`. It comes from the mlx dependency bundle, not from this change.
  timestamp: 2026-10-08T22:24:23.035498+00:00
- actor: claude-code
  id: 01m4esw97nhshsz88q81nzh95e
  text: |-
    ### implement — changed
    - evidence: RED `optionalResultFieldIsDeclaredNullable` failed (declared `alert?: string`); GREEN passed. `swift build --build-tests` OK; `swift test` 2327 tests in 205 suites passed, 0 failures. Files: Sources/FoundationModelsMultitool/Surface/ToolAPIRenderer.swift, Sources/FoundationModelsMultitool/Surface/ToolSignature.swift, Tests/FoundationModelsMultitoolTests/ToolAPIRendererTests.swift, Tests/FoundationModelsMultitoolTests/Fixtures/ToolAPIRendererFixtures.swift.
    - next: /review
  timestamp: 2026-10-08T22:24:25.845740+00:00
- actor: claude-code
  id: 01m4et6j5g7nz44jbbess2egfh
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (77ad02c). 0 findings, 0 confirmed, 0 refuted. 7 validator runs, 0 failed. 4 source files reviewed. 4 .kanban files not reviewed (.reviewignore).
    - next: none. The task moved to done.
  timestamp: 2026-10-08T22:30:02.672436+00:00
- actor: claude-code
  id: 01m4et6zy48b0g2eee00dr2yys
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — ToolAPIRenderer.swift, ToolSignature.swift, 2 test files
    - test: green — swift test, 2327 passed
    - commit: 77ad02c
    - review: clean — 0 findings; task in done
  timestamp: 2026-10-08T22:30:16.772923+00:00
position_column: done
position_ordinal: ffffd180
title: Declare an optional result field as `T | null` in the rendered `@returns` type
---
## What
Task ^efqdpfn changed `ArgumentMarshaler.renderOutput(_:)`: a `nil` optional field of a `@Generable` result now reaches a `runCode` snippet as `null`. The rendered result type of `ToolAPIRenderer` (`declaredType(ofObject:)` in `Sources/FoundationModelsMultitool/Surface/ToolAPIRenderer.swift`) still writes such a field as `name?: T`. That type says "missing or `T`", not "`null` or `T`".

The same renderer writes the `args` object type. For an argument, `name?: T` is correct, because a snippet omits an optional argument.

Decide if the result type must show `null` (for example `name?: T | null`, or `name: T | null`) and change only the result side.

## Acceptance Criteria
- [x] The rendered result type of a tool with a `@Generable` `Output` agrees with what a snippet reads for a `nil` optional field.
- [x] The rendered `args` type does not change.

## Tests
- [x] A unit test in `ToolAPIRendererTests` for a result with an optional field.
- [x] Run `swift test` — all tests pass. #environment