---
assignees:
- claude-code
depends_on:
- 01M4GAP3C6RWJRQQ42PES7P0FD
position_column: todo
position_ordinal: '8280'
title: Add the tools.files.removeDirectory verb
---
## What

Add a verb that removes a directory. At this time, the files capability cannot remove a directory, and the model must use `tools.shell.execute`. The `PathGuard` rule `.delete` accepts only a regular file (`checkDeletePermission` in `Sources/FoundationModelsMultitool/Capabilities/Files/PathGuard.swift`), so this verb must do its own directory checks. (The change to the `Write` description is in the alias task that comes after this task.)

- [ ] Make `Sources/FoundationModelsMultitool/Capabilities/Files/RemoveDirectory.swift`. Use the same pattern as `Write.swift`: a `@Generable struct RemoveDirectoryArguments`, a `@Generable struct RemoveDirectoryResult`, and `struct RemoveDirectory: Tool` with `let name = "removeDirectory"` and `let context: FileContext`.
  - Arguments: `path: String`, and `recursive: Bool?`. When `recursive` is nil, use `false`.
  - Result: `path: String` (the absolute path, empty on a correction), `removed: Bool`, `filesRemoved: Int`, and `correction: String?`.
- [ ] Put the rules in `call(arguments:)`. Each failure is a correction. The verb never throws:
  - If `context.readOnly` is true, send back a correction.
  - Validate with `context.pathGuard.validate(_:for: .directory)`.
  - If nothing is at the path, send back a correction.
  - If the path is a regular file, send back a correction that tells the model to delete a file with `tools.files.patch`.
  - If the resolved path is `context.root`, or a workspace root of `context.pathGuard` (`workspaceRoot` or an additional root), send back a correction.
  - If the path is a symlink to a directory, remove the link only. Do not follow it.
  - If the directory is not empty and `recursive` is false, send back a correction that names `recursive: true`.
  - Before the removal, when `context.changes.isRecording` is true, make one `FileChange(kind: .delete, ...)` for each regular file under the directory, with its old text (`AtomicWriter.decodedText(at:)`). After the removal, call `context.changes.commit(_:through:)` with `ToolContext.current` (read one time, at the start of `call`).
  - Set `filesRemoved` to the number of regular files that the removal deleted.
  - Write a `description` that tells the model what the verb does and when to use it.
- [ ] Add `RemoveDirectory(context: context)` to `FilesCapability.tools` in `Sources/FoundationModelsMultitool/Capabilities/Files/FilesCapability.swift`, after `MakeDirectory`. Change the verb count in the comments and add a row to the verb table in the doc comment.
- [ ] In `README.md`, section "### Files", add `removeDirectory` to the list of verbs and change the verb count.

## Acceptance Criteria

- [ ] `tools.files.removeDirectory({ path: "empty" })` removes an empty directory, and the result has `removed: true`, `filesRemoved: 0`, and no `correction`.
- [ ] On a directory that holds files, a call with no `recursive` gives a `correction` and nothing is removed. A call with `recursive: true` removes the tree, and `filesRemoved` is the number of files.
- [ ] A missing path, a regular file, the session root, a path outside the root, and a call on a read-only session each give a `correction`. Nothing on the disk changes.
- [ ] A symlink to a directory is removed, and the target directory and its files stay.
- [ ] On a session with `recordsChanges: true`, a recursive removal records one `.delete` change for each removed file, with its old content.
- [ ] `FilesCapability(root:).tools.map(\.name)` contains `removeDirectory`.

## Tests

- [ ] Make `Tests/FoundationModelsMultitoolTests/FilesRemoveDirectoryTests.swift`. Use the same setup as `FilesWriteTests.swift` (a temporary root and `RemoveDirectory(context:)` called directly). Add one test for each acceptance criterion above. For the change journal, use `FileContext(root: root, recordsChanges: true)` and `await context.changes.drain().changes`, as `FilesWriteTests.swift` does.
- [ ] In `Tests/FoundationModelsMultitoolTests/FilesCapabilityTests.swift`, add `"removeDirectory"` to the `filesVerbs` array, in the render order.
- [ ] Run `swift test --filter "FilesRemoveDirectoryTests|FilesCapabilityTests"`. All tests pass. Then run `swift test`. All tests pass.

## Workflow

- Use `/tdd` — write failing tests first, then implement to make them pass.