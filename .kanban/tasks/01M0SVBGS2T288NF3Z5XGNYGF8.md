---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0ttagmkdqdrncs2dpmbsht0
  text: |-
    Picked up. Research done.

    Read before planning:
    - `Sources/FoundationModelsMultitool/Capabilities/Shell/Execute.swift` — the verb already answers a blank command and an unparsable environment in band, through `Self.corrected(_:)`, which renders `{"correction": "..."}` with `ResultRenderer`. New checks land in the same style, in the `// MARK: - The requests this verb refuses` extension.
    - `Tests/FoundationModelsMultitoolTests/ShellExecuteTests.swift` — has a `Self.call(_:_:under:)` helper that binds `ToolContext`, and a `Self.report(_:)` helper that reads the answer as JSON.
    - The sibling's policy file, lines 86, 90 and 701. The three value checks are: length cap, no null byte, no CR and no LF.

    Two discoveries the card did not state:

    1. **`ShellPermissionRemovalTests` bans the string `ShellPolicy` in every source and test file.** The sibling's file NAME holds that string, so no doc comment here may name the file. Each new comment names it as "the sibling shell tool's settings defaults" instead.

    2. **A search for the Character `"\n"` cannot answer the CR/LF check.** Swift reads a CR LF pair as ONE grapheme cluster, which equals neither `"\r"` nor `"\n"`, so the sibling's `value.contains("\n") || value.contains("\r")` passes a value holding `\r\n`. The port therefore reads `value.utf8` for all three checks, which is what the byte-measurement requirement asks for anyway.

    Plan: `maximumCommandLengthBytes = 262_144` and `maximumEnvironmentValueLengthBytes = 1024` as named constants; an `EnvironmentValueDefect` enum carrying the three checks as data (a switch over a closed enum, which the `data-driven` rule states IS the table); one message shape that names the failed check, the cap and the measured byte length. `ShellRunner` is not touched.
  timestamp: 2026-08-24T21:20:18.067085+00:00
- actor: claude-code
  id: 01m0ttjcbf9asnf08azv76zvfv
  text: |-
    Implementation landed, under TDD.

    RED first: the six new cases were written before the code and the run failed with `type 'Execute' has no member 'maximumCommandLengthBytes'`. GREEN after: 19 cases in `ShellExecuteTests`, then 577 cases over 46 suites, all passing.

    What the verb now holds, all in `Execute.swift`:

    - `maximumCommandLengthBytes = 262_144` and `maximumEnvironmentValueLengthBytes = 1024`, both `internal` so a test can stand one byte over the cap and one byte under it without writing the number twice.
    - `EnvironmentValueDefect`, a `CaseIterable` enum of the three ported checks — `.overLength`, `.embeddedNull`, `.embeddedLineBreak`. A closed enum switch IS the table the `data-driven` rule asks for, so the three checks are data rather than a chain of `if` statements.
    - `commandTooLongCorrection(measuring:)` and `EnvironmentValueDefect.correction(forValueNamed:measuring:)`. One message shape for all three value defects, thus every message names the failed check, the cap AND the measured byte length.
    - `environmentRefusal(in:)` reads the entries in the order of their names. A dictionary carries no order, and without the sort a map with two bad values would name a different one on each call, which reads as two mistakes.

    Two things worth carrying forward:

    1. **The byte tests read `value.utf8`, not the Characters.** A search for the Character `"\n"` cannot answer the CR/LF check: Swift reads a CR LF pair as ONE grapheme cluster that equals neither `"\r"` nor `"\n"`, so the sibling's `value.contains("\n") || value.contains("\r")` passes a value holding `\r\n` — the exact injection this check exists to stop. `anEnvironmentValueHoldingACarriageReturnLineFeedPairAnswersWithACorrection` pins it.

    2. **No comment names the sibling's policy FILE.** `ShellPermissionRemovalTests` bans the string `ShellPolicy` in every source and test file, and the file name holds it. Each new comment says "the sibling shell tool's settings defaults" instead.

    Also updated: the file header comment, which stated these caps were out of scope, and the model-facing `description`, which now names the two new refusals so the model reads them before it makes the call.

    `ShellRunner.swift` is untouched — `git diff --stat` on it is empty.
  timestamp: 2026-08-24T21:24:35.823489+00:00
- actor: claude-code
  id: 01m0ttjjxms8apy52bp8p2teav
  text: |-
    ### implement — changed
    - evidence: 2 files — Sources/FoundationModelsMultitool/Capabilities/Shell/Execute.swift, Tests/FoundationModelsMultitoolTests/ShellExecuteTests.swift (347 insertions, 9 deletions). `swift test`: 577 tests in 46 suites, 0 failures, 0 compiler warnings. 7 of 7 acceptance criteria and 6 of 6 test items checked.
    - next: /review
  timestamp: 2026-08-24T21:24:42.548756+00:00
- actor: claude-code
  id: 01m0ttyvfqmabc0yw02j8aa721
  text: |
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (ed69210) — 0 findings, 0 confirmed, 0 refuted, 7 validators attempted, 0 failed. 2 files reviewed (`Execute.swift`, `ShellExecuteTests.swift`); 6 `.kanban/` files excluded by `.reviewignore`.
    - verified: every check on the validation path reads the UTF-8 bytes, and no path measures or scans by Character. Command length `arguments.command.utf8.count` (Execute.swift:268); value length `value.utf8.count` (Execute.swift:680); NUL `value.utf8.contains` (Execute.swift:682); CR and LF `value.utf8.contains` (Execute.swift:684-685); reported length `value.utf8.count` (Execute.swift:635). The byte test for the line break is necessary, not only a measure: Swift reads a CR LF pair as one grapheme cluster that equals neither `"\r"` nor `"\n"`, thus a Character search passes the pair. A byte scan for 0x00, 0x0A and 0x0D also gives no false result, because a UTF-8 lead byte and a continuation byte are always 0x80 or more.
    - next: no open finding. Task moved to done.
  timestamp: 2026-08-24T21:31:24.535163+00:00
- actor: claude-code
  id: 01m0ttzmhyyepfjj8sbwsbyz4k
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 2 files (Capabilities/Shell/Execute.swift, Tests/ShellExecuteTests.swift), 347 insertions and 9 deletions. Both caps ported at the sibling's numbers, and all three environment-value checks, not the length alone. Six new test cases, written first and watched fail.
    - test: green — swift test run twice, 577 passed in 46 suites, 0 failed, 0 skipped. No stray process after either run.
    - commit: ed69210 feat(shell): validate command and environment byte limits in execute verb
    - review: clean — zero findings; the task is in done.

    **A defect in the sibling that this port does not carry.** Every check reads `value.utf8` rather than the Characters. That is not only the byte-measurement requirement of the card: Swift reads a CR LF pair as ONE extended grapheme cluster that equals neither `"\r"` nor `"\n"`, thus the sibling's `value.contains("\n") || value.contains("\r")` passes a value holding `\r\n` — the exact injection the check exists to stop. A test pins that pair.

    The reviewer verified the claim against the code and added the reason the byte scan gives no false result: every UTF-8 lead byte and continuation byte is 0x80 or more, thus bytes 0x00, 0x0A and 0x0D can only be those ASCII scalars themselves.

    `../FoundationModelsShelltool` still carries the broken Character-based check. That is worth a card on the Shelltool board.
  timestamp: 2026-08-24T21:31:50.206121+00:00
depends_on:
- 01M0NAKY7B8H1Z0J2VCBWV86SY
position_column: done
position_ordinal: f080
title: Validate the command and environment in the tools.shell.execute verb
---
## What

`ShellPolicy` is deleted, thus **no layer examines the command text or the
environment values**. `ShellRunner.swift:288-291` deferred that work to the
policy. The checks must land somewhere, and the verb layer is the right place:
`ShellRunner.Outcome` (lines 172-184) holds `status` and `exitCode` only, thus
it has no channel for a message, and this package puts a corrective result in
the verb — see `GetLines.swift:171` and `GrepHistory.swift:159`.

So this task adds the validation to the `tools.shell.execute` verb that
`^bwv86sy` creates. It does not touch `ShellRunner`.

Port from `../FoundationModelsShelltool/Sources/ShellTool/ShellPolicy.swift`:

- The command-length cap, `defaultMaxCommandLength = 262_144` (line 86).
- The environment-value checks at line 701: a value must be within the length
  cap `defaultMaxEnvValueLength = 1024` (line 90), **hold no null byte, and hold
  no CR and no LF**. Port all three. The NUL and CR/LF checks are the
  injection-relevant ones; do not drop them.

**Measure bytes, not characters.** The sibling uses `command.count` (line 550)
and `value.count` (line 716), which count grapheme clusters. Use `utf8.count`.
The limit these caps stand in front of is `E2BIG` from `posix_spawn`, which
counts the bytes of the argv and envp block, and UTF-8 text can be several times
longer in bytes than in characters.

Every failure gives a **corrective result in band**, and is never thrown:
eventplan.md § "Consolidation of the siblings" states that a corrective result
stays in band. The message names which check failed, the cap, and the measured
length in bytes.

## Acceptance Criteria

- [x] The execute verb rejects a command whose UTF-8 length is over 262_144.
- [x] The execute verb rejects an environment value over 1024 UTF-8 bytes.
- [x] The execute verb rejects an environment value holding NUL.
- [x] The execute verb rejects an environment value holding CR or LF.
- [x] Each rejection is a corrective result in band. Nothing is thrown.
- [x] Each message names the failed check, the cap, and the measured byte length.
- [x] `ShellRunner` is not modified by this task.

## Tests

- [x] New cases in the execute verb's test file, which `^bwv86sy` creates.
- [x] A command one byte over the cap gives the corrective result, and nothing
      is thrown.
- [x] A command exactly at the cap runs.
- [x] A multi-byte UTF-8 command under the character count but over the byte cap
      is rejected. This is the case that a `Character` count would miss.
- [x] An environment value over the cap, one holding NUL, and one holding CR/LF
      each give the corrective result.
- [x] `swift test` passes with no new failure and no new warning.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #phase-2 #eventplan