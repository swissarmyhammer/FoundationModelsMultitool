---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0t1gs3ses0xafybkskff95q
  text: |-
    Picked up. Research done.

    Facts confirmed in the tree:
    - `grep ShellDotfolder.` over `Sources/` and `Tests/` finds exactly one `Sources/` caller: `ShellState.swift` calls `ShellDotfolder.currentDirectory()`. Nothing in `Sources/` calls `userURL(fileName:environment:)` or `projectURL(fileName:)`.
    - `ShellDotfolderTests.swift` calls both resolvers (3 cases on `userURL`, 1 on `projectURL`), so periphery indexes a caller for each and reports neither. The `dead-code-swift` validator supersedes the `dead-code` prompt rule for Swift files, and where a tool decides, the tool decides — so no `// periphery:ignore` marker is owed here, and adding one would mark a declaration the tool never reports.
    - `ShellPermissionRemovalTests.swift` already states in its suite doc comment that `config.yaml` is not banned and that `ShellDotfolder.configFileName` was kept on purpose.
    - `SeatbeltSandbox.Options.writableRoots` / `.extraWritePaths` are supplied by code alone today; no card on the board plans a config reader.

    Decision taken: **KEEP both resolvers**, option 1 of the card.

    Reasons:
    - `^5325spr` kept `configFileName` one day ago with a written reason that names these two resolvers as how a future reader finds that file in each layer. Deleting them makes that written reason false.
    - Deleting them does not stop at two names. `name` is read only by `userLayerRoot` and `projectURL`, and `configFileName` has no meaning without a resolver, so option 2 collapses `ShellDotfolder` to a one-line wrapper over `FileManager.default.currentDirectoryPath` and makes the file header false as well. That is a wider change than this card scopes, and it reverses a decision recorded a day earlier.
    - The XDG lookup and the git-root walk are small, correct and tested. A later config reader would have to write them again.

    `Yams` is NOT re-added. Nothing in this change touches `Package.swift`.
  timestamp: 2026-08-24T14:06:48.953834+00:00
- actor: claude-code
  id: 01m0t1nsvq3nj4zrcsvktykm7n
  text: |-
    Implementation landed. One file changed, doc comments only, no behaviour change.

    `Sources/FoundationModelsMultitool/Capabilities/Shell/ShellDotfolder.swift`
    - `configFileName` — a third paragraph binds the three names: this constant,
      `userURL(fileName:environment:)` and `projectURL(fileName:)` stand or fall
      together, and a change that deletes one must read the reason on the other two
      again. The two paragraphs `^5325spr` wrote are untouched and still read true.
    - `userURL(fileName:environment:)` — a paragraph states that no file of
      `Sources/` calls it yet, that it is kept on purpose as the user half of the
      pair that finds `configFileName`, that the reader of that file is the caller
      that lands, and that `ShellDotfolderTests` holds the XDG lookup correct until
      then.
    - `projectURL(fileName:)` — the same for the project half, pointing at the
      reason on `configFileName` rather than repeating it.

    `/tdd` red-green does not apply: no production behaviour changed, no symbol
    gained or lost a signature, and the four existing cases of
    `ShellDotfolderTests` already pin both resolvers. No test was added, weakened
    or removed.

    Verification:
    - `swift test` — 562 tests in 46 suites passed.
    - `swift build --build-tests` after touching the changed file — 1 warning, the
      pre-existing SwiftPM build-system line `missing creator for mutated node:
      .../mlx-swift_Cmlx.bundle/Contents/MacOS`. Zero Swift compiler warnings.
    - `swift test --filter 'ShellDotfolder|ShellState|ShellPermissionRemoval'` — 42
      tests in 4 suites passed, `ShellPermissionRemoval` included, so no banned
      name came back.
    - `periphery scan` with the flag set `dead-code-swift` states, test target
      report-excluded: zero findings for `ShellDotfolder.swift`. The whole scan
      reports only `var.parameter` rows in `JSCInterpreter.swift`, which that rule
      drops.

    Note for a later reader: the repository carries no `.swift-format` file and its
    CI (`.github/workflows/ci.yml`) runs no format or lint step, so a bare
    `swift-format lint` run judges the tree against the 2-space default and
    disagrees with the project's 4-space style everywhere. That is the default
    configuration talking, not this change; the added lines sit at the indentation
    of their neighbours.
  timestamp: 2026-08-24T14:09:33.559852+00:00
- actor: claude-code
  id: 01m0t1nzxh8x0d23enjvvqst81
  text: |-
    ### implement — changed
    - evidence: 1 file — /Users/wballard/github/swissarmyhammer/FoundationModelsMultitool/Sources/FoundationModelsMultitool/Capabilities/Shell/ShellDotfolder.swift (+19 lines, doc comments only). `swift test`: 562 tests in 46 suites passed. `periphery`: 0 findings for that file.
    - next: /review
  timestamp: 2026-08-24T14:09:39.761832+00:00
position_column: doing
position_ordinal: '8380'
title: Decide the fate of ShellDotfolder.userURL and projectURL, which no Sources file calls
---
## What

Found while doing `^5325spr`, and left alone there because that card scopes to
four constants only.

`ShellDotfolder` has two layer resolvers:

- `userURL(fileName:environment:)`
- `projectURL(fileName:)`

No file of `Sources/` calls either one. The one member of the type that a
`Sources/` file calls is `currentDirectory()`, from `ShellState`.

`periphery` stays silent about both, because `ShellDotfolderTests` calls them
and the scan indexes the test targets. So the tool reports nothing, and the
question is a design question rather than a dead-code finding.

The two resolvers are the reason `configFileName` was kept in `^5325spr`: they
are how a future reader of the shell `config.yaml` finds the file in each of
the two layers. So the answer here is bound to the answer there.

## What to decide

One of these, and write the reason in the file:

1. Keep both, because the config reader that `configFileName` waits for is the
   caller that lands. State that in the doc comment of each one, the way
   `configFileName` states it now.
2. Delete both with their tests, and let the config reader bring back the
   resolution it needs. `configFileName` then has to be looked at again too,
   because the reason its doc comment gives names these two resolvers.

Do not leave the two with no caller and no note.

## The decision that was made

**Option 1. Both resolvers are KEPT, each with a written reason in its doc
comment.**

- `userURL(fileName:environment:)` — KEPT. Its doc comment now states that no
  file of `Sources/` calls it yet and that it is kept on purpose: it is the
  user half of the pair that finds `configFileName`, the reader of that file is
  the caller that lands, and `ShellDotfolderTests` holds the XDG lookup correct
  until then.
- `projectURL(fileName:)` — KEPT. Its doc comment states the same for the
  project half, and points at the reason written on `configFileName`.
- `configFileName` — its reason still reads true, because both resolvers stand.
  A third paragraph now binds the three names: they stand or fall together, and
  a change that deletes one must read the reason on the other two again.

Why option 1 rather than option 2:

- `^5325spr` kept `configFileName` one day earlier with a written reason that
  names these two resolvers. Deleting them makes that reason false.
- The delete does not stop at two names. `name` is read only by
  `userLayerRoot` and `projectURL`, and `configFileName` has no meaning with no
  resolver, so option 2 collapses `ShellDotfolder` to a one-line wrapper over
  `FileManager.default.currentDirectoryPath` and makes the file header false.
  That is wider than this card, and it reverses a decision recorded a day
  earlier.
- The XDG lookup and the git-root walk are small, correct and tested. A later
  config reader would have to write them again.

No `// periphery:ignore` marker was written. `dead-code-swift` supersedes the
`dead-code` prompt rule for Swift files, the tool reports neither resolver
because the test target indexes a caller for each, and a marker on a
declaration the tool never reports states nothing.

## Acceptance Criteria

- [x] `userURL` and `projectURL` are each deleted, or kept with a written
      reason in the doc comment.
- [x] The reason written on `configFileName` still reads true after the change.
- [x] `swift test` passes with no new failure and no new warning.
- [x] `periphery` reports nothing new for `ShellDotfolder.swift`.

#phase-2 #eventplan