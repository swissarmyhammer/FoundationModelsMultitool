---
assignees:
- claude-code
position_column: todo
position_ordinal: '8980'
title: Give a nil optional field of a verb result to a runCode snippet as null, not as a missing key
---
## What
`ArgumentMarshaler.renderOutput(_:)` (`Sources/FoundationModelsMultitool/Invocation/ArgumentMarshaler.swift`) reads `GeneratedContent.jsonString` of a `@Generable` result. That text has no key for a `nil` property. Thus in a snippet a `nil` field such as `correction` is `undefined`, not `null`. Each `@Guide` text of a `correction` field says "null when ... stands", thus a model that writes `r.correction === null` gets `false`.

Found in task ^pykbc2k: `EnvironmentGoalSnippetTests` shows that `tools.environment.variables` gives no `correction` key. The same is true for each capability (git, files, web, environment).

Decide one of these and do it for all capabilities:
- Render each `nil` optional property of a result as JSON `null` (walk the `GenerationSchema` of the output type, or the content tree), or
- Change each Guide text from "null" to "missing", if missing is the contract.

## Acceptance Criteria
- [ ] A snippet reads a `nil` optional field of a verb result in the way that its Guide text says.
- [ ] `EnvironmentGoalSnippetTests` "the nil correction reaches the snippet as a missing value" is changed to match the decision.

## Tests
- [ ] A unit test in `ArgumentMarshalerTests` for a `@Generable` result with a `nil` optional field.
- [ ] Run `swift test` — all tests pass. #environment