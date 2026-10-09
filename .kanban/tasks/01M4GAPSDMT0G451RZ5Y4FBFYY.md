---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4gfhpeewe9p7m93rn48r3yw
  text: |-
    Research done.
    - `PathGuard.validate(_:for: .directory)` refuses a regular file with "Path exists but is not a directory". Thus the verb uses `validatePath`, then its own checks (missing, regular file -> patch correction), then `checkPermission(_:for: .directory)`. The result is the same rule set as `validate(_:for: .directory)`, with the patch correction first.
    - `PathGuard` refuses a path that is a symlink when `allowSymlinks` is false (the default). Thus the symlink criterion applies only on a session with `allowSymlinks: true`. With `allowSymlinks: true`, `validatePath` gives the canonical TARGET of the link, not the link. The verb must find the link path itself and must bound the parent folder of the link, or a link under an outside folder could be removed.
    - `allWorkspaceRoots` and `canonicalize` are private in `PathGuard`. The root check needs canonical paths (macOS temporary folders are under `/var` -> `/private/var`). Plan: add an internal `PathGuard` method that tells if a URL is the session root or a workspace root.
    - `FileWalker.collectFiles(walkRoot:respectGitIgnore: false)` gives the regular files under a folder (it does not follow a symlink). Reuse it for the journal and the count.
    - Verb-count text "seven" stands in FilesCapability.swift, MultiToolBuilder+Capabilities.swift, FilesRunFixtures.swift, FilesCapabilityTests.swift and README.md (commit d70205c changed the same places).
  timestamp: 2026-10-09T14:02:22.030647+00:00
- actor: claude-code
  id: 01m4gg4egnezknfme40dzpke5s
  text: |-
    Implementation landed (TDD: the new suite did not compile before the verb existed; then 24 of 24 green in the two suites).

    Divergences from the card, each to follow the existing design:
    - Validation: `validate(_:for: .directory)` refuses a regular file with "Path exists but is not a directory" before the verb can give the `tools.files.patch` correction. Thus the verb runs `validatePath`, then its own checks (missing, regular file, root), then `checkPermission(_:for: .directory)`. The rule set is the same; only the order changes.
    - Symlink: `PathGuard` refuses a symlink path when `allowSymlinks` is false (the secure default). Thus the symlink criterion applies on a session with `allowSymlinks: true`, and the test uses that session. With symlinks on, `validatePath` gives the TARGET, so a new `PathGuard.validateSymlinkLocation(_:)` gives the location of the link and bounds its parent folder. Test `linkInAFolderOutsideTheRootIsCorrective` holds that a link in an outside folder (with a target inside the root) is not removed.
    - The symlink check comes before the root check: removing a link never removes a root.

    PathGuard additions: `validateSymlinkLocation(_:)`, `isRoot(_:)` (realpath on both sides, because temporary folders are under /var -> /private/var), private `absolutePath(of:)`, and private `trimmingTrailingSlashes(_:)` extracted from `parentPath(_:)`.
    Reuse: `FileWalker.collectFiles(walkRoot:respectGitIgnore: false)` lists the files; `PathCorrective.pathErrorMessage` builds each message; `resolveAsync` resolves the corrections.
    A removal that fails part of the way commits only the changes of files that are gone, and the correction carries their count in `filesRemoved`.
    Other edits: verb count seven -> eight in FilesCapability.swift, MultiToolBuilder+Capabilities.swift, FilesRunFixtures.swift, FilesCapabilityTests.swift, README.md; `recordsChanges` docs name `removeDirectory`; `PlainToolContractTests.capturingVerbFiles` adds RemoveDirectory.swift (the full run failed on that list before this change).
    Not changed: the `Write` description still names tools.shell.execute for a directory; the card puts that in the alias task 01M4GAQ52PZQCX8FZ6Q2C3KCP9 (the task that this task blocks).
  timestamp: 2026-10-09T14:12:36.501430+00:00
- actor: claude-code
  id: 01m4gg4yzw3c3qc2x5y0fxzsrq
  text: |-
    ### implement — changed
    - evidence: `swift build --build-tests` clean (only the SwiftPM "missing creator ... mlx-swift_Cmlx.bundle" build-system note, not from the code). `swift test --filter "FilesRemoveDirectoryTests|FilesCapabilityTests"`: 24 of 24 pass. Full `swift test`: 2357 tests in 208 suites, 1 failure (PlainToolContractTests.filesVerbsReadTheAmbientContextOneTimeAtTheStart, the capture list); after the fix `swift test --filter PlainToolContractTests`: 13 of 13 pass. Files: RemoveDirectory.swift (new), FilesRemoveDirectoryTests.swift (new), PathGuard.swift, FilesCapability.swift, MultiToolBuilder+Capabilities.swift, README.md, FilesCapabilityTests.swift, FilesRunFixtures.swift, PlainToolContractTests.swift.
    - next: /review. The task stays in doing.
  timestamp: 2026-10-09T14:12:53.372014+00:00
- actor: claude-code
  id: 01m4gghpz3fnh8gq4g8nmmdsx4
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (5d58fd4). 0 findings, 0 confirmed, 1 refuted, 7 attempted, 0 failed. 8 files reviewed. README.md had no matching validator. The .kanban/ files are excluded by .reviewignore. No prior review findings were on the task.
    - next: none. The task moved to done.
  timestamp: 2026-10-09T14:19:51.139056+00:00
- actor: claude-code
  id: 01m4ggj4dgs6rtzahrgg13rfmc
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 9 files (new RemoveDirectory.swift, PathGuard.isRoot / validateSymlinkLocation, tests)
    - test: green — full swift test, 2357 passed
    - commit: 5d58fd4
    - review: clean — 0 findings; task in done
  timestamp: 2026-10-09T14:20:04.912372+00:00
depends_on:
- 01M4GAP3C6RWJRQQ42PES7P0FD
position_column: done
position_ordinal: ffffd580
title: Add the tools.files.removeDirectory verb
---
## What

Add a verb that removes a directory. At this time, the files capability cannot remove a directory, and the model must use `tools.shell.execute`. The `PathGuard` rule `.delete` accepts only a regular file (`checkDeletePermission` in `Sources/FoundationModelsMultitool/Capabilities/Files/PathGuard.swift`), so this verb must do its own directory checks. (The change to the `Write` description is in the alias task that comes after this task.)

- [x] Make `Sources/FoundationModelsMultitool/Capabilities/Files/RemoveDirectory.swift`. Use the same pattern as `Write.swift`: a `@Generable struct RemoveDirectoryArguments`, a `@Generable struct RemoveDirectoryResult`, and `struct RemoveDirectory: Tool` with `let name = "removeDirectory"` and `let context: FileContext`.
  - Arguments: `path: String`, and `recursive: Bool?`. When `recursive` is nil, use `false`.
  - Result: `path: String` (the absolute path, empty on a correction), `removed: Bool`, `filesRemoved: Int`, and `correction: String?`.
- [x] Put the rules in `call(arguments:)`. Each failure is a correction. The verb never throws:
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
- [x] Add `RemoveDirectory(context: context)` to `FilesCapability.tools` in `Sources/FoundationModelsMultitool/Capabilities/Files/FilesCapability.swift`, after `MakeDirectory`. Change the verb count in the comments and add a row to the verb table in the doc comment.
- [x] In `README.md`, section "### Files", add `removeDirectory` to the list of verbs and change the verb count.

## Acceptance Criteria

- [x] `tools.files.removeDirectory({ path: "empty" })` removes an empty directory, and the result has `removed: true`, `filesRemoved: 0`, and no `correction`.
- [x] On a directory that holds files, a call with no `recursive` gives a `correction` and nothing is removed. A call with `recursive: true` removes the tree, and `filesRemoved` is the number of files.
- [x] A missing path, a regular file, the session root, a path outside the root, and a call on a read-only session each give a `correction`. Nothing on the disk changes.
- [x] A symlink to a directory is removed, and the target directory and its files stay.
- [x] On a session with `recordsChanges: true`, a recursive removal records one `.delete` change for each removed file, with its old content.
- [x] `FilesCapability(root:).tools.map(\.name)` contains `removeDirectory`.

## Tests

- [x] Make `Tests/FoundationModelsMultitoolTests/FilesRemoveDirectoryTests.swift`. Use the same setup as `FilesWriteTests.swift` (a temporary root and `RemoveDirectory(context:)` called directly). Add one test for each acceptance criterion above. For the change journal, use `FileContext(root: root, recordsChanges: true)` and `await context.changes.drain().changes`, as `FilesWriteTests.swift` does.
- [x] In `Tests/FoundationModelsMultitoolTests/FilesCapabilityTests.swift`, add `"removeDirectory"` to the `filesVerbs` array, in the render order.
- [x] Run `swift test --filter "FilesRemoveDirectoryTests|FilesCapabilityTests"`. All tests pass. Then run `swift test`. All tests pass.

## Workflow

- Use `/tdd` — write failing tests first, then implement to make them pass.