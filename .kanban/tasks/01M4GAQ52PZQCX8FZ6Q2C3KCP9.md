---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4ggpxezrcp2aw40b4txmygy
  text: 'Research: `verbAliasResolution(for:in:snippet:knownPaths:)` compares the verb in lowercase against `VerbAlias.verbs`, and answers only when the group is real and the row path is in the surface. Thus the two new rows need no code change other than the table. The `Write` description today says "tools.shell.execute removes a file or a whole directory". `MakeDirectory` says that write does not make absent folders, thus the `Write` description also names `tools.files.makeDirectory` for a folder that is not there (the dispatcher asked for create and remove). No test reads the `Write` description today. The new description tests read behavior: every `tools.*` path that the description names (through `UnknownToolHint.referencedToolPaths(in:)`) is a verb of the files capability, and the two directory verb paths (built from the verb `name` properties) are among them. No test copies the wording.'
  timestamp: 2026-10-09T14:22:41.631120+00:00
- actor: claude-code
  id: 01m4gh8t7zatbhdgxrpfpxywq3
  text: |-
    Implementation landed (TDD). RED: the 3 new alias tests and the 2 new Write description tests failed for the missing feature. GREEN: two rows added to `verbAliases` with a doc comment that gives their source (the same intent in the words of a shell: mkdir, rmdir, and the spelled-out forms). The `Write` description now names `tools.files.makeDirectory` for an absent folder and `tools.files.removeDirectory` for a whole directory, and no longer names `tools.shell.execute`. Addition beyond the card text: the dispatcher asked that the description send both create and remove to the new verbs, thus it also names makeDirectory. The description tests read behavior, not wording: every `tools.*` path in the description is a files verb, and both directory verb paths (built from the verb `name` properties) are present. Discovery: three test suites already hold a private `verb(_:in:)` cast helper; the new tests build the verbs from a `FileContext` instead, to add no fourth copy. The build prints `warning: missing creator for mutated node` for the mlx-swift_Cmlx bundle on every build; it comes from the build system, not from this change.

    ### implement — changed
    - evidence: Sources/FoundationModelsMultitool/Discovery/UnknownToolHint.swift, Sources/FoundationModelsMultitool/Capabilities/Files/Write.swift, Tests/FoundationModelsMultitoolTests/VerbAliasHintTests.swift, Tests/FoundationModelsMultitoolTests/FilesWriteTests.swift; `swift build --build-tests` complete; filtered run 49 tests in 3 suites pass; `swift test` 2362 tests in 208 suites pass
    - next: review
  timestamp: 2026-10-09T14:32:28.159076+00:00
- actor: claude-code
  id: 01m4ghj8y4gqxenft6s811m2vr
  text: |-
    Coordinator correction applied: the user does not want a test that pins or bans wording. `theDescriptionNamesTheDirectoryVerbs()` required text in the `Write` description, thus I deleted it. `pathsNamedByTheDescription(in:)` stays, because `everyPathTheDescriptionNamesIsAFilesVerb()` uses it. Effect: no test now holds the acceptance criterion "The Write description names tools.files.removeDirectory". The source change meets it, and `everyPathTheDescriptionNamesIsAFilesVerb()` stops a return to `tools.shell.execute`.

    ### implement — changed
    - evidence: same 4 files; `swift build --build-tests` complete; `swift test` 2361 tests in 208 suites pass
    - next: review
  timestamp: 2026-10-09T14:37:38.116481+00:00
- actor: claude-code
  id: 01m4gjy6t51y57dp4hgm5ey885
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (923aee7). 0 findings, 0 confirmed, 0 refuted. 7 validator runs, 0 failed. 4 source and test files reviewed. 4 .kanban files not reviewed (.reviewignore). No file renames.
    - next: none. The task is in done.
  timestamp: 2026-10-09T15:01:37.733235+00:00
- actor: claude-code
  id: 01m4gjyq01knnwm0gfzef158sf
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — UnknownToolHint.swift, Write.swift, 2 test files; the wording test theDescriptionNamesTheDirectoryVerbs was removed (user rule)
    - test: green — full swift test, 2361 passed
    - commit: 923aee7
    - review: clean — 0 findings; task in done
  timestamp: 2026-10-09T15:01:54.305102+00:00
depends_on:
- 01M4GAP3C6RWJRQQ42PES7P0FD
- 01M4GAPSDMT0G451RZ5Y4FBFYY
position_column: done
position_ordinal: ffffd680
title: 'Point the model at the directory verbs: mkdir and rmdir alias hints, and the Write description'
---
## What

A model that uses shell words calls `tools.files.mkdir` or `tools.files.rmdir`. These paths do not exist. Add rows to the alias table, so that the error names the real verb. The alias only names the real path. It does not call it (see the doc comment of `UnknownToolHint` near `verbAliases`: a call hides the mistake from the model and from the `imaginedTool` log).

Also, the `description` of `Write` tells the model to remove a directory with `tools.shell.execute`. After the `removeDirectory` task, this text is wrong.

- [x] In `Sources/FoundationModelsMultitool/Discovery/UnknownToolHint.swift`, add two rows to `private static let verbAliases`. The verbs must be in lowercase:
  - `VerbAlias(path: "files.makeDirectory", verbs: ["mkdir", "makedir", "createdirectory", "createdir", "newdirectory"])`
  - `VerbAlias(path: "files.removeDirectory", verbs: ["rmdir", "removedir", "deletedirectory", "deletedir"])`
- [x] Change the doc comment of `verbAliases` so that it gives the source of the two new rows: the same intent in the words of a shell.
- [x] In `Sources/FoundationModelsMultitool/Capabilities/Files/Write.swift`, change the `description` property of `Write`: to remove a directory, it must name `tools.files.removeDirectory`, not `tools.shell.execute`.

## Acceptance Criteria

- [x] With the files capability mounted, a snippet that calls `tools.files.mkdir` fails with a hint that names `tools.files.makeDirectory`, and the resolution has `tier == .verbAlias`.
- [x] A snippet that calls `tools.files.rmdir` fails with a hint that names `tools.files.removeDirectory`, and `tier == .verbAlias`.
- [x] `tools.files.MkDir` gets the same hint as `tools.files.mkdir` (the match is not sensitive to case).
- [x] The old rows (`files.glob`, `shell.execute`) give the same hints as before.
- [x] The `Write` description names `tools.files.removeDirectory`.

## Tests

- [x] In `Tests/FoundationModelsMultitoolTests/VerbAliasHintTests.swift`, add tests with the same form as `filesFindIsAnsweredWithGlob()`: `filesMkdirIsAnsweredWithMakeDirectory()`, `filesRmdirIsAnsweredWithRemoveDirectory()`, and a mixed-case test for `MkDir`. Use the `resolve(_:includesFiles:)` method of that suite.
- [x] Run `swift test --filter "VerbAliasHintTests|UnknownToolHintTests|FilesWriteTests"`. All tests pass. Then run `swift test`. All tests pass.

## Workflow

- Use `/tdd` — write failing tests first, then implement to make them pass.