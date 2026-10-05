---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m46dm5jk8ac8ejqzrkjw2kj0
  text: |-
    Research:
    - `ToolInvoker.invoke` calls `validate(content, against: tool.parameters, ...)`, then `T.Arguments(content)`. `validate` decodes the schema itself through `decodeArgumentsSchema`. Plan: decode the schema one time in `invoke`, normalize the content against it, then give the same normalized content to `validate` and to `T.Arguments`.
    - `ArgumentPropertySchema` does not read `items` now. Add an `items` field (only its `type`) so the normalize step can see a string element type.
    - The test fixtures have `CountedTool` (`ratings: [Int]`, count 1...3). Use it for the "number stays a type error" and the "string for [Int] is not coerced" tests.
    - `FilesCrossOpFlowTests` has the `runCode` harness (`run(_:root:)`) and an edit flow with `find: [anchor]`. Add the scalar find/replace flow there.
  timestamp: 2026-10-05T16:16:21.587716+00:00
- actor: claude-code
  id: 01m46e2h86mj7eanrtab4y4emg
  text: |-
    Implementation done:
    - `ToolInvoker.invoke` decodes the schema one time, then calls the new `wrappingStringsInStringArrays(_:against:)`. That function changes a `.string` value to a one-item `.array` only when the property schema is `type: "array"` and `items.type` is `"string"` or is absent. `validate` and `T.Arguments(...)` both read the normalized content. `validate` now takes the decoded `ArgumentsSchema`, so the schema is not decoded two times.
    - `ArgumentPropertySchema` now reads `items` (through the new `ArgumentItemSchema`, element `type` only). It also has `isStringArray`, with the named constants `arrayType` and `stringType`.
    - `validateType` did not change, so a number for an array, or a string for `[Int]`, still gives the same `.typeMismatch` message (the tests pin the exact message).
    - The `find` and `replace` `@Guide` text in `Edit.swift` now gives the array example and says that one string is also accepted.
    - RED was confirmed before the fix: the invoker test failed with `Tool "labelsTool" argument "labels" must be array, got a string instead.`, and the runCode edit test failed with `Tool "edit" argument "find" must be array, got a string instead.` The two guard tests (number for array, string for [Int]) passed before and after, as expected, because they pin behavior that must not change.
    - Note: the full run shows the SwiftPM warning `missing creator for mutated node` for the `mlx-swift_Cmlx.bundle`. This is a build-graph warning from a dependency, not a compiler warning from the source.
  timestamp: 2026-10-05T16:24:12.294501+00:00
- actor: claude-code
  id: 01m46e5f8d41vtbyf29n2s561t
  text: |-
    ### implement — changed
    - evidence: 5 files — Sources/FoundationModelsMultitool/Invocation/ToolInvoker.swift, Sources/FoundationModelsMultitool/Capabilities/Files/Edit.swift, Tests/FoundationModelsMultitoolTests/ToolInvokerTests.swift, Tests/FoundationModelsMultitoolTests/Fixtures/ToolInvokerFixtures.swift, Tests/FoundationModelsMultitoolTests/FilesCrossOpFlowTests.swift. `swift test --filter "ToolInvokerTests|FilesCrossOpFlowTests/aScalar"`: RED 2 failed of 16, then GREEN 16 of 16 passed. `swift build` succeeded; `swift test` full suite: 1812 tests in 151 suites passed, 0 failed (XCTest: 0 tests). No compiler warnings.
    - next: /review
  timestamp: 2026-10-05T16:25:48.557685+00:00
- actor: claude-code
  id: 01m46eeyxb9m29pnnr9gb7qrm9
  text: |-
    ### test - green
    - evidence: swift test - 1812 tests in 151 suites passed, 0 failed, 0 skipped, 0 warnings from our code. IntegrationTests: swift build --build-tests failed first (mlx-swift submodule clean error, stale pins), so swift package update ran. Then the build failed: ScenarioRunner.swift "switch must be exhaustive" (new Router cases .compactionStarted, .compactionFailed). Fixed in IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Support/ScenarioRunner.swift. Rebuild: Build complete, 0 errors.
    - warning: "missing creator for mutated node" for mlx-swift_Cmlx.bundle/Contents/MacOS. It comes from the mlx-swift dependency resource bundle in the SwiftPM build system. We have no such target. It is not in our code. It shows in both the root package and IntegrationTests builds.
    - next: review
  timestamp: 2026-10-05T16:30:59.499979+00:00
position_column: doing
position_ordinal: '80'
title: 'Tool arguments: accept a string where the schema has an array of strings (edit find/replace)'
---
## Problem

In the SWE-bench run (reported by the FoundationModelsACPAgent session), this was the most frequent real tool error. It occurred on most instances:

`Tool "edit" argument "find" must be array, got a string instead.` (ToolInvokerError code 1, log message `tools argument validation failed`)

Each time, the model fixes the snippet and calls again. Each retry costs one generation.

## Where

- `Sources/FoundationModelsMultitool/Capabilities/Files/Edit.swift:39-77`: `EditArguments` has `var find: [String]?` and `var replace: [String]?`. The `@Guide` text says "one for a single edit, several for a batch", but it gives no example of the array form.
- `Sources/FoundationModelsMultitool/Invocation/ToolInvoker.swift:313-387`: `validate(_:against:toolName:)` and `validateType(...)`. Line 376: `case ("array", .array)`. A `.string` value for an `"array"` schema throws `.typeMismatch` (line 384 gives the message).
- After validation, the invoker makes `T.Arguments(content)`. The coercion must change the `GeneratedContent` before that step, not only skip the check.
- `ArgumentPropertySchema` (same file or near it) holds `type`; check if it also reads `items`, so the code can see that the items are strings.
- The same error can occur on each tool that has an array-of-strings argument (for example `replace`, and other `files`/`shell` arguments). Thus a general fix in the invoker is better than a fix only in `Edit`.

## Fix

1. In the invoker, before `validate`, normalize the arguments: for each property whose schema has `type: "array"` and `items.type: "string"` (or no `items` type), if the value is a `.string`, replace it with an `.array` that holds that one string. A string is the same as an array with one item.
2. Do this only for a string to an array of strings. Do not coerce other kinds (number to array, object to array). Those stay type errors.
3. Keep `validateType` as it is, thus a wrong kind still gives the same clear message.
4. Also add a short example to the `find` and `replace` `@Guide` text of `Edit`, for example: `find: ["old text"], replace: ["new text"]`. Write in the description that one string is also accepted.
5. Add a doc comment on the normalize function that gives the reason (the SWE-bench evidence).

## Tests

- Invoker test: a tool with an `[String]?` argument, called with a string, gets an array with one item, and the call succeeds.
- `tools.files.edit` test through `runCode` (pattern of the existing edit tests): `{ path, find: "a", replace: "b" }` applies the edit, the same as `find: ["a"], replace: ["b"]`.
- A number for an array argument still throws `.typeMismatch` with the same message.
- A string for a `[Int]` argument (if such a tool exists in the tests) is not coerced.

## Acceptance

- `swift build` and `swift test` pass with no new warnings. #defect #operation-tools