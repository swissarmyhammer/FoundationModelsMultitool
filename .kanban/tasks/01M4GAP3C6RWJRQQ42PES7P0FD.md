---
assignees:
- claude-code
position_column: todo
position_ordinal: '8180'
title: Add the tools.files.makeDirectory verb
---
## What

Add a verb that makes a directory. At this time, the files capability cannot make a directory. A `write` to a path whose parent folder is absent gets the correction "Parent directory does not exist" (`PathGuard.AbsentFolderRule.refused`). Thus the model must use `tools.shell.execute`.

- [ ] Make `Sources/FoundationModelsMultitool/Capabilities/Files/MakeDirectory.swift`. Use the same pattern as `Write.swift`: a `@Generable struct MakeDirectoryArguments`, a `@Generable struct MakeDirectoryResult`, and `struct MakeDirectory: Tool` with `let name = "makeDirectory"` and `let context: FileContext`.
  - Arguments: `path: String`, and `parents: Bool?`. When `parents` is nil, use `true`.
  - Result: `path: String` (the absolute path, empty on a correction), `created: Bool`, and `correction: String?`.
- [ ] Put the rules in `call(arguments:)`:
  - If `context.readOnly` is true, send back a correction. Do not throw.
  - Validate with `context.pathGuard.validatePath(_:absentFolders:)`. Use `.accepted` when `parents` is true, and `.refused` when `parents` is false. Then use `context.pathGuard.checkPermission(_:for: .directory)`. Each violation is a correction.
  - If a directory is at the path, send back `created: false` and no correction.
  - If a file (not a directory) is at the path, send back a correction.
  - Make the directory with `FileManager.default.createDirectory(at:withIntermediateDirectories:)`, with `withIntermediateDirectories` equal to `parents`. If this fails, send back a correction.
  - Do not record a change in `context.changes`. A patch cannot show an empty directory.
  - Write a `description` that tells the model what the verb does and when to use it.
- [ ] Add `MakeDirectory(context: context)` to `FilesCapability.tools` in `Sources/FoundationModelsMultitool/Capabilities/Files/FilesCapability.swift`, after `Write`. Change "six verbs" to the correct count in the comments and add a row to the verb table in the doc comment.
- [ ] In `README.md`, section "### Files", add `makeDirectory` to the list of verbs and change the verb count.

## Acceptance Criteria

- [ ] `tools.files.makeDirectory({ path: "a/b/c" })` makes the three folders under `root`, and the result has `created: true` and no `correction`.
- [ ] With `parents: false` and the folder `a` absent, the result has a `correction` and no folder is made.
- [ ] A second call on the same path gives `created: false` and no `correction`.
- [ ] A path where a file already is, a path outside `root`, and a call on a read-only session each give a `correction`. Nothing on the disk changes. The verb does not throw.
- [ ] `FilesCapability(root:).tools.map(\.name)` contains `makeDirectory`.

## Tests

- [ ] Make `Tests/FoundationModelsMultitoolTests/FilesMakeDirectoryTests.swift`. Use the same setup as `FilesWriteTests.swift` (a temporary root and `MakeDirectory(context:)` called directly). Add one test for each acceptance criterion above.
- [ ] In `Tests/FoundationModelsMultitoolTests/FilesCapabilityTests.swift`, add `"makeDirectory"` to the `filesVerbs` array, in the render order.
- [ ] Run `swift test --filter "FilesMakeDirectoryTests|FilesCapabilityTests"`. All tests pass. Then run `swift test`. All tests pass.

## Workflow

- Use `/tdd` — write failing tests first, then implement to make them pass.