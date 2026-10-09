---
assignees:
- claude-code
depends_on:
- 01M4GAP3C6RWJRQQ42PES7P0FD
- 01M4GAPSDMT0G451RZ5Y4FBFYY
position_column: todo
position_ordinal: '8380'
title: 'Point the model at the directory verbs: mkdir and rmdir alias hints, and the Write description'
---
## What

A model that uses shell words calls `tools.files.mkdir` or `tools.files.rmdir`. These paths do not exist. Add rows to the alias table, so that the error names the real verb. The alias only names the real path. It does not call it (see the doc comment of `UnknownToolHint` near `verbAliases`: a call hides the mistake from the model and from the `imaginedTool` log).

Also, the `description` of `Write` tells the model to remove a directory with `tools.shell.execute`. After the `removeDirectory` task, this text is wrong.

- [ ] In `Sources/FoundationModelsMultitool/Discovery/UnknownToolHint.swift`, add two rows to `private static let verbAliases`. The verbs must be in lowercase:
  - `VerbAlias(path: "files.makeDirectory", verbs: ["mkdir", "makedir", "createdirectory", "createdir", "newdirectory"])`
  - `VerbAlias(path: "files.removeDirectory", verbs: ["rmdir", "removedir", "deletedirectory", "deletedir"])`
- [ ] Change the doc comment of `verbAliases` so that it gives the source of the two new rows: the same intent in the words of a shell.
- [ ] In `Sources/FoundationModelsMultitool/Capabilities/Files/Write.swift`, change the `description` property of `Write`: to remove a directory, it must name `tools.files.removeDirectory`, not `tools.shell.execute`.

## Acceptance Criteria

- [ ] With the files capability mounted, a snippet that calls `tools.files.mkdir` fails with a hint that names `tools.files.makeDirectory`, and the resolution has `tier == .verbAlias`.
- [ ] A snippet that calls `tools.files.rmdir` fails with a hint that names `tools.files.removeDirectory`, and `tier == .verbAlias`.
- [ ] `tools.files.MkDir` gets the same hint as `tools.files.mkdir` (the match is not sensitive to case).
- [ ] The old rows (`files.glob`, `shell.execute`) give the same hints as before.
- [ ] The `Write` description names `tools.files.removeDirectory`.

## Tests

- [ ] In `Tests/FoundationModelsMultitoolTests/VerbAliasHintTests.swift`, add tests with the same form as `filesFindIsAnsweredWithGlob()`: `filesMkdirIsAnsweredWithMakeDirectory()`, `filesRmdirIsAnsweredWithRemoveDirectory()`, and a mixed-case test for `MkDir`. Use the `resolve(_:includesFiles:)` method of that suite.
- [ ] Run `swift test --filter "VerbAliasHintTests|UnknownToolHintTests|FilesWriteTests"`. All tests pass. Then run `swift test`. All tests pass.

## Workflow

- Use `/tdd` — write failing tests first, then implement to make them pass.