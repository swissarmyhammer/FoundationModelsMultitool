---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4gdzwnj86j38trmgfwn7prt
  text: |-
    Research done.
    - `PathGuard.checkPermission(_:for: .directory)` (via `checkDirectoryPermission`) already refuses a path where a non-directory item is, with "Path exists but is not a directory". Thus the "file at the path" correction comes from the guard; the verb needs no separate check for it.
    - `validatePath(_:absentFolders: .accepted)` gives the uncanonicalized absolute URL for a nested absent path, and the boundary check still applies from the deepest present folder.
    - `Result.resolveAsync`/`resolve(corrective:then:)` in CorrectiveResult.swift is the shared resolution shape. `validatePath(...).flatMap { checkPermission(...).map { url } }` is the same composition `PathGuard.validate(_:for:)` uses, but `validate` has no `absentFolders` parameter.
    - PlainToolContractTests scans the Files folder for `ToolContext.current`; the new verb must not read it (it records no change, so it has no need).
    - "six verbs" text also stands in `Surface/MultiToolBuilder+Capabilities.swift` (doc of `withFiles`) and in FilesCapabilityTests names; these get the new count.
  timestamp: 2026-10-09T13:35:10.002290+00:00
- actor: claude-code
  id: 01m4gefqjj7mvnr334h217820n
  text: |-
    Implementation landed (TDD: FilesMakeDirectoryTests failed to compile before the verb existed; FilesCapabilityTests failed 8 issues before the capability held the verb; both green after).
    - Design note: the card says use `validatePath(_:absentFolders:)` then `checkPermission(_:for: .directory)`. `PathGuard.validate(_:for:)` already composes these two, but had no `absentFolders` parameter. I extended `validate(_:for:absentFolders:)` with a default of `.refused` (the reuse rule: extend the near-match). All existing callers keep the old behavior.
    - Design note: the "file at the path" correction comes from the guard (`checkDirectoryPermission` gives "Path exists but is not a directory"), as the existing design does. The verb does not repeat that check.
    - The verb does not read `ToolContext.current`, thus the reflective guard in PlainToolContractTests stays green.
    - Stale "six verbs" text changed in FilesCapability.swift, MultiToolBuilder+Capabilities.swift (`withFiles` doc), README.md, FilesCapabilityTests.swift, Fixtures/FilesRunFixtures.swift. PlainToolContractTests and FilesCrossOpFlowTests still say "six": they cover the six verbs they exercise, and neither exercises makeDirectory.
    - Build note: `swift build` prints "warning: missing creator for mutated node ... mlx-swift_Cmlx.bundle". That is a build-system warning from the mlx dependency bundle, not a compiler warning in this code.

    ### implement — changed
    - evidence: `swift build --build-tests` clean (no compiler warning); `swift test --filter "FilesMakeDirectoryTests|FilesCapabilityTests"` 18 tests in 2 suites passed; `swift test` 2345 tests in 207 suites passed. Files: Sources/.../Files/MakeDirectory.swift (new), Sources/.../Files/PathGuard.swift, Sources/.../Files/FilesCapability.swift, Sources/.../Surface/MultiToolBuilder+Capabilities.swift, README.md, Tests/.../FilesMakeDirectoryTests.swift (new), Tests/.../FilesCapabilityTests.swift, Tests/.../Fixtures/FilesRunFixtures.swift
    - next: /review
  timestamp: 2026-10-09T13:43:49.074337+00:00
position_column: doing
position_ordinal: '80'
title: Add the tools.files.makeDirectory verb
---
## What

Add a verb that makes a directory. At this time, the files capability cannot make a directory. A `write` to a path whose parent folder is absent gets the correction "Parent directory does not exist" (`PathGuard.AbsentFolderRule.refused`). Thus the model must use `tools.shell.execute`.

- [x] Make `Sources/FoundationModelsMultitool/Capabilities/Files/MakeDirectory.swift`. Use the same pattern as `Write.swift`: a `@Generable struct MakeDirectoryArguments`, a `@Generable struct MakeDirectoryResult`, and `struct MakeDirectory: Tool` with `let name = "makeDirectory"` and `let context: FileContext`.
  - Arguments: `path: String`, and `parents: Bool?`. When `parents` is nil, use `true`.
  - Result: `path: String` (the absolute path, empty on a correction), `created: Bool`, and `correction: String?`.
- [x] Put the rules in `call(arguments:)`:
  - If `context.readOnly` is true, send back a correction. Do not throw.
  - Validate with `context.pathGuard.validatePath(_:absentFolders:)`. Use `.accepted` when `parents` is true, and `.refused` when `parents` is false. Then use `context.pathGuard.checkPermission(_:for: .directory)`. Each violation is a correction.
  - If a directory is at the path, send back `created: false` and no correction.
  - If a file (not a directory) is at the path, send back a correction.
  - Make the directory with `FileManager.default.createDirectory(at:withIntermediateDirectories:)`, with `withIntermediateDirectories` equal to `parents`. If this fails, send back a correction.
  - Do not record a change in `context.changes`. A patch cannot show an empty directory.
  - Write a `description` that tells the model what the verb does and when to use it.
- [x] Add `MakeDirectory(context: context)` to `FilesCapability.tools` in `Sources/FoundationModelsMultitool/Capabilities/Files/FilesCapability.swift`, after `Write`. Change "six verbs" to the correct count in the comments and add a row to the verb table in the doc comment.
- [x] In `README.md`, section "### Files", add `makeDirectory` to the list of verbs and change the verb count.

## Acceptance Criteria

- [x] `tools.files.makeDirectory({ path: "a/b/c" })` makes the three folders under `root`, and the result has `created: true` and no `correction`.
- [x] With `parents: false` and the folder `a` absent, the result has a `correction` and no folder is made.
- [x] A second call on the same path gives `created: false` and no `correction`.
- [x] A path where a file already is, a path outside `root`, and a call on a read-only session each give a `correction`. Nothing on the disk changes. The verb does not throw.
- [x] `FilesCapability(root:).tools.map(\.name)` contains `makeDirectory`.

## Tests

- [x] Make `Tests/FoundationModelsMultitoolTests/FilesMakeDirectoryTests.swift`. Use the same setup as `FilesWriteTests.swift` (a temporary root and `MakeDirectory(context:)` called directly). Add one test for each acceptance criterion above.
- [x] In `Tests/FoundationModelsMultitoolTests/FilesCapabilityTests.swift`, add `"makeDirectory"` to the `filesVerbs` array, in the render order.
- [x] Run `swift test --filter "FilesMakeDirectoryTests|FilesCapabilityTests"`. All tests pass. Then run `swift test`. All tests pass.

## Workflow

- Use `/tdd` — write failing tests first, then implement to make them pass.