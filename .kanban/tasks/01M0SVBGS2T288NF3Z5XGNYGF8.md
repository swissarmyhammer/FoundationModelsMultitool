---
assignees:
- claude-code
depends_on:
- 01M0NAKY7B8H1Z0J2VCBWV86SY
position_column: todo
position_ordinal: '9380'
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

- [ ] The execute verb rejects a command whose UTF-8 length is over 262_144.
- [ ] The execute verb rejects an environment value over 1024 UTF-8 bytes.
- [ ] The execute verb rejects an environment value holding NUL.
- [ ] The execute verb rejects an environment value holding CR or LF.
- [ ] Each rejection is a corrective result in band. Nothing is thrown.
- [ ] Each message names the failed check, the cap, and the measured byte length.
- [ ] `ShellRunner` is not modified by this task.

## Tests

- [ ] New cases in the execute verb's test file, which `^bwv86sy` creates.
- [ ] A command one byte over the cap gives the corrective result, and nothing
      is thrown.
- [ ] A command exactly at the cap runs.
- [ ] A multi-byte UTF-8 command under the character count but over the byte cap
      is rejected. This is the case that a `Character` count would miss.
- [ ] An environment value over the cap, one holding NUL, and one holding CR/LF
      each give the corrective result.
- [ ] `swift test` passes with no new failure and no new warning.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #phase-2 #eventplan