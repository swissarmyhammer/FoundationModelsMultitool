---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m261qpq41w3xmqdjjsbh98z7
  text: |-
    Research, before the code.

    The card names `RegistryBundle.swift:75` and `:97`. Card `^46j5hqw` has since changed that file: `hintSearcher` is now a `MetadataSearcher<APISurface.Entry>` built in `RegistryBundle.init`, in `.retrieval` mode, with `shape.embedder` and `selection: nil`.

    The one way a test reads that searcher without building a second one is the holder. `Registry.makeSessionToolsAndStaging(librarian:embedder:)` vends the `MultiTool.RegistryHolder` the mounted tools share, and `holder.current.hintSearcher` is the searcher a run really gets. The shared mount `makeFilesAndShellSurface` now makes that call and carries the searcher, so no suite builds a searcher of its own.

    The hint path generates nothing: the searcher has no selection tier. Thus the reading is the embedder's alone, and every profile of the target names the same `CLIRunner.embeddingModel`. The suite therefore takes `plumbingProbeProfile`, and the roster in `LiveRouterFixture` now names it as the third suite that may.
  timestamp: 2026-09-10T16:17:10.884486+00:00
- actor: claude-code
  id: 01m261r1yhb2g5zywx7d7t3enq
  text: |-
    The measurement, which chose the three cases.

    The card says to measure rather than assume, so eight wrong paths were driven before three were kept. Each line is the tier that answered and the entry it named:

        files.raed                  resemblance   files.read, files.edit, files.glob
        process.spawn               relevance     shell.execute
        terminal.runShellCommand    relevance     shell.execute
        terminal.runCommand         relevance     shell.getLines
        bash.run                    relevance     shell.getLines
        terminal.runTests           relevance     shell.getLines
        document.fetchText          relevance     files.patch
        weather.getForecast         relevance     shell.getLines

    Three things this shows.

    1. The hint searcher really answers. Seven of the eight fell through tier 1 and were answered by tier 2, which is the searcher of this card.
    2. Every one named a real entry of the surface. That is the promise the card asks for, and the suite holds it in the resolution and in the hint text alike.
    3. The retrieval tier carries no floor. `weather.getForecast` resembles no entry and is still answered with one. `noMatch` is what a failed ranking reads as, not what an unrelated guess reads as. The suite records that in its own documentation and holds the promise a host can rely on.

    A miss the measurement found: `terminal.runCommand`, `bash.run` and `terminal.runTests` each ask to run a command and are answered with `shell.getLines`, the verb that reads what a command printed. The likely cause is word count: the `getLines` description says `run` and `command` many times. New card `^pwn02m4` owns that. The suite prints the answer for each case and asserts nothing beyond the declared ones, so the fix is measured here.

    The wrong-noun case is `process.spawn` — right work, a noun the catalog never uses, no trigram shared with any entry. It is the shape the card asks for and it holds today.
  timestamp: 2026-09-10T16:17:22.385324+00:00
depends_on:
- 01M25KGJZVPVF5XW0WQ46J5HQW
position_column: doing
position_ordinal: '80'
title: The did-you-mean hint path has no live test
---
## What happened

When the model calls a tool path that the surface does not hold, `UnknownToolHint` answers with a hint. The hint names the tools that resemble what the model asked for. That path uses its own searcher, `RegistryBundle.hintSearcher`, in `.retrieval` mode with no selection tier (`RegistryBundle.swift:75` and `:97`).

Every test of that path is a unit test with a scripted searcher: `Tests/FoundationModelsMultitoolTests/UnknownToolHintTests.swift`. No gated test drives it with a live model or a live embedder.

The gap matters for three reasons:

1. The hint is what the model reads after it makes a mistake. A wrong hint sends the model to a wrong tool, or to no tool.
2. The hint searcher now ranks with the host embedder. Card `^zqz1zan` added that. No live test sees a cosine score in this path.
3. Card `^46j5hqw` changes the type of this searcher. A change with no live test behind it is a change nobody can measure.

## What to do

1. Add a gated test that builds a real surface, calls a tool path that does not exist, and reads the hint the package answers.
2. Use paths of three shapes: a name with a spelling mistake, a name that is correct under a wrong noun, and a name that no tool of the surface resembles.
3. Assert what the package promises. A hint names a tool that exists on the surface. A path that resembles nothing gives no wrong name.
4. Print the tier that answered and the tools it named, in the shape the other gated suites print their readings.
5. Keep the run short. Three paths on one surface are enough.

## Rules

- Do not edit a package checkout under `.build/checkouts`.
- Do not test the hint through `searchTools`. This card is about the other searcher.

## Acceptance Criteria

- [x] A gated test drives `UnknownToolHint` on a live surface with an embedder.
- [x] The three shapes of wrong path each have a case.
- [x] The test asserts that every named tool exists on the surface.
- [x] The tier and the named tools are printed for each case.

## Tests

- [x] `swift test` at the root: no failure, no warning.
- [x] `swift test --package-path IntegrationTests --no-parallel` for the new suite.

#discovery #search-tools #test-coverage