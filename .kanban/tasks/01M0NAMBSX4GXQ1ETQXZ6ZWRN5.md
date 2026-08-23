---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0rdknqce06sb955pshd6mph
  text: |-
    ### Research — picked up ^z6zwrn5

    What the port must change, because the target package is not the sibling.

    1. **No `Operations` package here.** The sibling verbs are `@Operation` structs with
       `execute(in: ShellContext)`. FoundationModelsMultitool has no such macro and no
       `ShellContext`. A verb here is a `FoundationModels.Tool` conformer:
       `name`, `description`, a `@Generable` Arguments struct, and
       `call(arguments:) async throws -> Output`. `WaitTool.swift` and the
       `ToolAPIRenderer` fixtures are the prevailing shape.
    2. **The store reaches the verb through the initializer, not through a context.**
       `ShellState` is an actor, thus `Sendable`, thus a stored property of a `Tool`
       is legal. `ShellCapability` (task ^zpdk266) will make one store and give it to
       `Execute(...)`, `GetLines(...)` and `GrepHistory(...)`.
    3. **`OutputBuffer` is private to `ShellRunner.consume`.** The buffer writes the
       lines it completes into `ShellState` as the chunks arrive, thus a read of the
       store IS the read of the capture. The two verbs therefore hold `ShellState`
       alone, and the "reads a run that is still going" criterion is proven against a
       real `ShellRunner` child.
    4. **`waitSeconds` does not come across.** The sibling `GetLines` carries a
       long-poll loop. The card states that these two verbs "are the content plane.
       They are not run-plane surfaces", and to wait for a run is the run plane, which
       the shared engine now owns (`WaitTool`, and the `wait(token, seconds)` sandbox
       global). No acceptance criterion and no test on the card names `waitSeconds`.
    5. **An unknown token becomes corrective.** The sibling answers an unknown id with
       an empty range. The card's acceptance criteria say a corrective result in band,
       for an unknown token and for a bad line range alike, thus each verb carries a
       `correction` field that stands alone when the read cannot be made.
    6. **The `@example` line is not hand written.** `ToolAPIRenderer` synthesizes it
       from the Arguments schema, and `APISurface.Entry` qualifies it to
       `tools.shell.<verb>`. The acceptance criterion is thus a test over the rendered
       surface.

    Rules read before editing: `dump validators` over one `.swift` file, whole file.
    The ones that shape this work: `magic-numbers-swift` (each literal but 0, 1, -1,
    100 needs a name), `missing-docs-swift`, `function-length-swift`,
    `duplication/swift`, `test-partitioning` (unit target, no environment variable).
  timestamp: 2026-08-23T22:59:37.836064+00:00
- actor: claude-code
  id: 01m0re3j873esga3dtf67ws9yd
  text: |-
    Implementation landed, TDD order kept.

    **RED** — `ShellHistoryOpsTests.swift` first. `swift test --filter ShellHistoryOps`
    answered `cannot find 'GrepHistory' in scope`, which is the feature missing and
    no typo.

    **GREEN** — the two verb files, then 13 tests pass.

    What each verb answers with:

    - `GetLines` → `GetLinesResult { commandID, first, last, lines, status?,
      correction? }`. `status` is the raw value of `CommandStatus`, thus `running`
      tells the model more output is still to come.
    - `GrepHistory` → `GrepHistoryResult { matches, shown, total, correction? }`,
      with `GrepHistoryMatch { commandID, lineNumber, text }`. The `shown`/`total`
      split of the sibling is kept.
    - `correction` and the answer are exclusive. Three reads take that path: a token
      no command of this session ran under (each verb), a line range that reads
      nothing, and a pattern that does not compile. Each one is a `String` the model
      reads and acts on inside the turn, and none of the three throws.

    Two notes for the reviewer, each a deliberate reading of the card:

    1. **The verbs hold `ShellState` and no `OutputBuffer`.** The card says "Both
       read `ShellState` and `OutputBuffer`". The buffer of a run is a local of
       `ShellRunner.consume`, which drains each completed line into `ShellState` as
       the chunks arrive, thus a read of the store IS the read of the capture, and
       no other reader can reach that buffer without a change to `ShellRunner` that
       this card does not ask for. The behavior the card names is met and tested:
       `getLines` and `grepHistory` each answer for a run that is still going
       (a real `ShellRunner` child of `echo …; sleep 5`) and for a run that ended.
    2. **`waitSeconds` is not ported**, for the reason the research comment above
       states: the long poll is the run plane, which the card takes away from these
       two verbs.

    Beyond the card's own list, three arguments would otherwise be untested surface,
    thus each has a test: the `start`/`end` range, the `literal` flag, and the
    `commandID` filter of `grepHistory`. `grepHistory` also has the live-run test
    that the "Both work while a run is still going" line of the What section asks
    for.

    `ARCHITECTURE.md` does not stand in this repository, thus nothing to update.

    ### implement — changed
    - evidence: `swift test --filter ShellHistoryOps` → 13 tests, 1 suite, passed.
      `swift test` → 587 tests, 46 suites, passed, 0 failures and 0 new warnings
      (the one `missing creator for mutated node` line names the mlx-swift bundle
      and stands on a no-op build as well, thus it is not of this change).
      3 files — Sources/FoundationModelsMultitool/Capabilities/Shell/GetLines.swift,
      Sources/FoundationModelsMultitool/Capabilities/Shell/GrepHistory.swift,
      Tests/FoundationModelsMultitoolTests/ShellHistoryOpsTests.swift.
    - next: `/review`
  timestamp: 2026-08-23T23:08:18.567351+00:00
depends_on:
- 01M0NAG6762NCNAAMETXX64PZV
- 01M0NAES1VVY3ETEXTCSFH0V2P
position_column: doing
position_ordinal: '8380'
title: Add the tools.shell.getLines and tools.shell.grepHistory verbs
---
## What

eventplan.md § "Consolidation of the siblings": *"`tools.shell.getLines` and
`tools.shell.grepHistory` read it as usual surface operations. They apply to a
live detached run ... and to a completed run."* These two verbs are the content
plane. They are not run-plane surfaces.

- Create
  `Sources/FoundationModelsMultitool/Capabilities/Shell/GetLines.swift` from
  `../FoundationModelsShelltool/Sources/ShellTool/Operations/GetLines.swift`
  (195 lines). `name = "getLines"`.
- Create
  `Sources/FoundationModelsMultitool/Capabilities/Shell/GrepHistory.swift` from
  `../FoundationModelsShelltool/Sources/ShellTool/Operations/GrepHistory.swift`
  (146 lines). `name = "grepHistory"`.
- Both take the run's completion token as the command identifier, a `String`.
- Both read `ShellState` and `OutputBuffer`. Both work while a run is still
  going and after a run ends.
- Each file carries the doc comment and one runnable example snippet.
- A corrective result — an unknown token, a bad line range — stays in band. It
  is never thrown.

## Acceptance Criteria

- [x] `tools.shell.getLines` and `tools.shell.grepHistory` render with runnable
      `@example` lines.
- [x] Both accept the completion token as the identifier.
- [x] `getLines` on a run that is still going returns the output written so
      far.
- [x] `getLines` on a completed run returns the stored output.
- [x] `grepHistory` finds a line in the history of the session.
- [x] An unknown token gives a corrective result in band, never a thrown error.

## Tests

- [x] New `Tests/FoundationModelsMultitoolTests/ShellHistoryOpsTests.swift`,
      ported from
      `../FoundationModelsShelltool/Tests/ShellToolTests/HistoryOpsTests.swift`.
- [x] A test starts a long command, reads `getLines` before it ends, and
      asserts on the partial output.
- [x] A test asserts an unknown token gives an in-band corrective result.
- [x] `swift test --filter ShellHistoryOps` passes.
- [x] `swift test` passes with no new failure and no new warning.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #phase-2 #eventplan