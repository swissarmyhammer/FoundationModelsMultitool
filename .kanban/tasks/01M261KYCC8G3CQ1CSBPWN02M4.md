---
assignees:
- claude-code
position_column: todo
position_ordinal: '8680'
title: The did-you-mean hint names the wrong shell verb for a run-a-command guess
---
## What happened

Card `^2rwvx3h` added `UnknownToolHintLiveTests`, the first gated test of the
did-you-mean path. It drives wrong `tools.*` paths against
`RegistryBundle.hintSearcher` — the retrieval-only ranker, with the shipped
embedder behind it — over the nine-entry files-and-shell surface.

Eight guesses were driven on 2026-09-10 to choose the cases of that suite.
Every one named a real entry of the surface, which is what the suite asserts.
But three of them named the wrong entry of the right capability:

    guess                       named            a reader says
    process.spawn               shell.execute    shell.execute
    terminal.runShellCommand    shell.execute    shell.execute
    terminal.runCommand         shell.getLines   shell.execute
    bash.run                    shell.getLines   shell.execute
    terminal.runTests           shell.getLines   shell.execute
    document.fetchText          files.patch      files.read
    weather.getForecast         shell.getLines   none

`terminal.runCommand` asks to run a command. The hint answers with the verb
that reads what a command already printed. A model that reads that hint calls
`tools.shell.getLines` with no completion token, and the repair fails a second
time.

The likely cause is a word count, not a meaning: the `shell.getLines`
description says `command` and `run` many times (`commandID`, "the output of a
run", "a run that is still going and a run that ended"), while
`shell.execute` says each word fewer times. A guess spelled with those two
words therefore ranks the reader above the runner.

## What to do

1. Measure which signal carries the miss. The retrieval tier fuses BM25 over
   two fields, character-trigram Dice and cosine. Read what each signal ranks
   for `run command` over these nine entries.
2. Correct the cause, not the case. The description of `shell.getLines` and
   the description of `shell.execute` are both the work of card `^p06rh7z`,
   and a wording fix must hold every reading that card measured.
3. Add the fixed guesses to `imaginedToolPaths` in
   `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/UnknownToolHintLiveTests.swift`
   with a declared best path, so the fix is held.

## Rules

- Do not edit a package checkout under `.build/checkouts`.
- Do not weaken an assertion of the gated suite to make a run green.

## Acceptance Criteria

- [ ] The signal that ranks `shell.getLines` over `shell.execute` for a
      run-a-command guess is named.
- [ ] `terminal.runCommand`, `bash.run` and `terminal.runTests` each answer
      with `shell.execute`.
- [ ] `AgentSurfaceDiscoveryTests` and `HeldOutSurfaceDiscoveryTests` hold
      their levels after the fix.

## Tests

- [ ] `swift test` at the root: no failure, no warning.
- [ ] `swift test --package-path IntegrationTests --no-parallel` for the
      gated suites.

#discovery #search-tools