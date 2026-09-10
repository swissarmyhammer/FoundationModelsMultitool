---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m26r0x4dng36ex0x84gqccev
  text: |
    The suspected cause on the card is not the cause, and the measurement says so.

    Word counts of the rendered blocks, over the nine-entry files-and-shell
    surface:

        entry              chars  tokens  trigrams  run  runs  command
        shell.execute       2164     358       703    8     2       14
        shell.getLines      1551     256       473    8     0        7
        shell.grepHistory   1844     292       528    7     1        4

    `shell.execute` holds MORE of each word than `shell.getLines`, not fewer. The
    BM25 list ranks `shell.execute` first for "terminal run command".

    Per-signal readings of the shipped hint searcher, with the shipped embedder:

        intent                 bm25            cosine          trigram
        terminal run command   shell.execute   shell.execute   shell.getLines
        bash run               shell.execute   shell.execute   shell.getLines
        terminal run tests     shell.execute   shell.execute   shell.getLines

    The trigram signal carries the miss. It is the Dice overlap of the character
    trigrams of the query with the character trigrams of the whole block. A
    three-word intent shares its trigrams with every block that holds the words,
    so the count of shared trigrams saturates and the score falls to the
    reciprocal of the size of the block. The runner renders the largest block of
    the nine and the reader the smallest, so the reader wins that list whatever
    the descriptions say.

    A wording fix was written, measured and thrown away. It changed the
    descriptions of `shell.getLines` and `shell.grepHistory` so that each named
    its own work instead of the runner's work. It moved `shell.execute` to first
    place on BM25 and on cosine for all three guesses, and the fusion of the three
    lists still answered `shell.getLines`. Do not try that road again: the trigram
    list is an order by block size, and no wording changes an order by size.
  timestamp: 2026-09-10T22:46:41.037615+00:00
- actor: claude-code
  id: 01m26r17edx5gy7eh9sjmdd9z0
  text: |
    ### implement — changed
    - evidence: The trigram signal carries the miss. It is a Dice overlap over the whole rendered block, so for a spelled-out intent it becomes an order by block size: `shell.execute` has the largest block of the nine (703 trigrams) and `shell.getLines` the smallest (473). BM25 and cosine each named `shell.execute` first for all three guesses; the trigram list outvoted them in the fusion. Fix: `MultiTool.hintSearchWeights` in `Sources/FoundationModelsMultitool/RegistryBundle.swift` drops the trigram weight for the hint searcher alone, because tier 1 of `UnknownToolHint` already answers a wrong spelling and `searchTools` keeps every signal. Files: `Sources/FoundationModelsMultitool/RegistryBundle.swift`, `Tests/FoundationModelsMultitoolTests/HintRankingTests.swift` (new fast guard, red before the fix and green after), `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/UnknownToolHintLiveTests.swift` (three cases added, no assertion weakened). The three guesses each answer `shell.execute` now: `terminal.runCommand` shell.execute, `bash.run` shell.execute, `terminal.runTests` shell.execute. `process.spawn` still answers shell.execute and `weather.getForecast` still answers shell.getLines. `swift test` at the root: 1423 tests in 114 suites passed, no warning. `swift build --package-path IntegrationTests`: clean. Gated suites, 6 tests in 6 suites passed: agentSurfaceDiscovery 19 correct and 3 wrong in each of 3 rounds; heldOutSurfaceDiscovery 16 and 2 in each of 3 rounds; retrievalTextChoice unchanged (agentSurface declaredTopThree 19, heldOut 16); noDescription and overBudget pass.
    - next: review
  timestamp: 2026-09-10T22:46:51.597483+00:00
- actor: claude-code
  id: 01m26r3js03861g2n7fkzxrxfb
  text: |-
    ### commit — changed
    - evidence: c4d586c fix(hint): stop the trigram signal from naming shell.getLines — 7 files changed
    - next: none. The task is ready for review.
  timestamp: 2026-09-10T22:48:08.736349+00:00
- actor: claude-code
  id: 01m26re6rfzb7cphszmnfb17r9
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` with the local engine over commit c4d586c. 0 findings, 0 confirmed, 0 refuted, 7 tries. The engine read RegistryBundle.swift, HintRankingTests.swift and UnknownToolHintLiveTests.swift. It did not read the four .kanban files, because an ignore rule holds them out. No earlier Review Findings list is on this card.
    - next: The card goes to done.
  timestamp: 2026-09-10T22:53:56.879751+00:00
- actor: claude-code
  id: 01m26resx6q40m151md8vjt58z
  text: |-
    ### finish iteration 1 — clean

    - implement: changed. The card named the wrong cause, and the measurement refuted it: `shell.execute` holds more of each word than `shell.getLines`. The true cause is the character-trigram signal. It is a Dice overlap over the whole rendered block, thus for a spelled-out intent the score falls to the reciprocal of the block size, and `shell.execute` renders the largest block of the nine. The keyword signal and the embedding signal each named `shell.execute` first, and the trigram list outvoted both. The fix drops the trigram weight for the hint searcher alone. A wording fix was written, measured and thrown away, and that dead end is on the card.
    - test: green. `swift test` gives 1423 pass in 114 suites, no warning. `swift build --package-path IntegrationTests` is clean. Six gated suites pass, and every count stays where it was.
    - commit: c4d586c, 7 files.
    - review: clean. 0 finding over `HEAD~1..HEAD`. The task moved to done.
  timestamp: 2026-09-10T22:54:16.486932+00:00
position_column: done
position_ordinal: ffc180
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

## What the measurement said

The suspected cause above is not the cause. The measurement of 2026-09-10 is
recorded in ``MultiTool/hintSearchWeights``:

- `shell.execute` says `command` 14 times and `run` 8 times in 358 tokens;
  `shell.getLines` says `command` 7 times and `run` 8 times in 256 tokens. The
  runner holds MORE of each word, not fewer.
- The BM25 list and the cosine list each named `shell.execute` first for all
  three guesses.
- The trigram list named `shell.getLines` first, and the fusion of the three
  lists followed it. The trigram signal is the Dice overlap of the character
  trigrams of the query with the character trigrams of the WHOLE block. A
  three-word intent shares its trigrams with every block that holds the words,
  so the score falls to the reciprocal of the size of the block.
  `shell.execute` renders the largest block of the nine (703 trigrams) and
  `shell.getLines` the smallest (480).

A wording fix cannot repair that. A trial rewording of `shell.getLines` and
`shell.grepHistory` was measured and thrown away: it moved `shell.execute` to
first place on BM25 and on cosine, and the fusion still answered
`shell.getLines`, because the trigram list is an order by block size.

The fix therefore stands where the searcher is built. `RegistryBundle` now
ranks the hint searcher with `MultiTool.hintSearchWeights`, which drops the
trigram weight. Tier 1 of `UnknownToolHint` already answers a wrong SPELLING
with the trigram overlap of the guessed name, and tier 2 is reached only when
tier 1 rejects the guess, so the trigram signal adds no meaning there.
`searchTools` keeps every signal.

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

- [x] The signal that ranks `shell.getLines` over `shell.execute` for a
      run-a-command guess is named.
- [x] `terminal.runCommand`, `bash.run` and `terminal.runTests` each answer
      with `shell.execute`.
- [x] `AgentSurfaceDiscoveryTests` and `HeldOutSurfaceDiscoveryTests` hold
      their levels after the fix.

## Tests

- [x] `swift test` at the root: no failure, no warning.
- [x] `swift test --package-path IntegrationTests --no-parallel` for the
      gated suites.

#discovery #search-tools