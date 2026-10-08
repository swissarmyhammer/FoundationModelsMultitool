---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4es09mr5kvvq44mszwkkenf
  text: |-
    Research and decision:
    - Decision: render `null`. The Guide texts say "null", and `ToolAPIRenderer` already reads each Output schema. Thus no Guide text changes.
    - Each capability verb (git, files, web, environment, and the shell verbs other than `execute`) is a real `Tool` with a `@Generable` Output, and goes through `SnippetOutput.value` -> `ArgumentMarshaler.renderOutput`. `OperationVerbTool` and `MCPTool` have `Output = GeneratedContent`. `tools.shell.execute` uses `SnippetOutputShaping.snippetValue` and does not reach `renderOutput`; it does not change.
    - Encoded schemas (probe, then deleted): an optional property is a property that is not in `required`; an optional nested `@Generable` is a `$ref` that is not in `required`. `GeneratedContent.generationSchema` is an `anyOf` ("Any legal JSON"), which `ToolAPIRenderer` reads as `.any`, thus a `GeneratedContent` output gets no `null` and the round-trip test stays the same.
    - Implementation: `ToolAPIRenderer.declaredShape(of:)` (internal) gives the `ToolValueShape` of a schema through the same decode and `shape(for:)` path as the `@returns` type (shared helper `returnShape(of:onWiden:)`). `renderOutput` reads that shape for a `Generable` Output type and adds `.null` for each declared optional property that the decoded value does not hold, at each level of objects and arrays. A missing required key stays missing. A schema that cannot be read throws the new `ArgumentMarshalerError.Kind.unreadableOutputSchema` (not reachable in practice: the render of each typed tool reads the same schema and stops its registration on failure).
    - The JSON-text parse from `24f65ed` (`jsonContainer`) runs first and is not changed.
    - Follow-up task ^fbses6j: the rendered result type still writes `name?: T` for such a field.
  timestamp: 2026-10-08T22:09:08.760589+00:00
- actor: claude-code
  id: 01m4es0cdabhpbr3yn3k6zsphq
  text: |-
    ### implement — changed
    - evidence: 4 files — Sources/FoundationModelsMultitool/Invocation/ArgumentMarshaler.swift, Sources/FoundationModelsMultitool/Surface/ToolAPIRenderer.swift, Tests/FoundationModelsMultitoolTests/ArgumentMarshalerTests.swift, Tests/FoundationModelsMultitoolTests/EnvironmentGoalSnippetTests.swift. RED: 2 new tests failed (missing `correction` key). GREEN: 2 passed. `swift build --build-tests` complete; `swift test`: 2326 tests in 205 suites passed, 0 failures. The one build warning is the SwiftPM "missing creator for mutated node" line for the mlx-swift_Cmlx bundle, which is not from this change.
    - next: /review
  timestamp: 2026-10-08T22:09:11.594950+00:00
- actor: claude-code
  id: 01m4esb818a255an3ksrycx9n1
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (e84e026). 0 findings, 0 confirmed, 1 refuted, 7 attempted, 0 failed. 4 source files reviewed. 6 .kanban files not reviewed (.reviewignore).
    - next: none. The task is in done.
  timestamp: 2026-10-08T22:15:07.560030+00:00
- actor: claude-code
  id: 01m4esbkpxeegsq6rg4sv82g56
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — ArgumentMarshaler.swift, ToolAPIRenderer.swift, 2 test files; new task ^fbses6j
    - test: green — swift test, 2326 passed
    - commit: e84e026
    - review: clean — 0 findings; task in done
  timestamp: 2026-10-08T22:15:19.517474+00:00
position_column: done
position_ordinal: ffffd080
title: Give a nil optional field of a verb result to a runCode snippet as null, not as a missing key
---
## What
`ArgumentMarshaler.renderOutput(_:)` (`Sources/FoundationModelsMultitool/Invocation/ArgumentMarshaler.swift`) reads `GeneratedContent.jsonString` of a `@Generable` result. That text has no key for a `nil` property. Thus in a snippet a `nil` field such as `correction` is `undefined`, not `null`. Each `@Guide` text of a `correction` field says "null when ... stands", thus a model that writes `r.correction === null` gets `false`.

Found in task ^pykbc2k: `EnvironmentGoalSnippetTests` shows that `tools.environment.variables` gives no `correction` key. The same is true for each capability (git, files, web, environment).

Decide one of these and do it for all capabilities:
- Render each `nil` optional property of a result as JSON `null` (walk the `GenerationSchema` of the output type, or the content tree), or
- Change each Guide text from "null" to "missing", if missing is the contract.

## Acceptance Criteria
- [x] A snippet reads a `nil` optional field of a verb result in the way that its Guide text says.
- [x] `EnvironmentGoalSnippetTests` "the nil correction reaches the snippet as a missing value" is changed to match the decision.

## Tests
- [x] A unit test in `ArgumentMarshalerTests` for a `@Generable` result with a `nil` optional field.
- [x] Run `swift test` — all tests pass. #environment