---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m25zecrt6hj58rznv53nds32
  text: |-
    ### research

    The hypothesis on the card is correct, and it holds for all nine entries and not only for the three shell verbs.

    `APISurface.Entry.summaryBlock` is `banner + qualify(descriptor.description)`. `APISurface+SearchableMetadata.renderSummaryBlock()` returns it, and `SelectionTier.assemblePrefix` puts one such block under a `## <id>` heading for each entry. Thus the description of a verb is the whole of what the selection model reads about it. Card `^0z0te3n` made it so.

    Each of the nine descriptions opened with what the verb does to its own data, and then gave its parameters. Examples of the text before the change:

    - `execute starts one shell command in the background and answers at once with its completion token.`
    - `getLines reads the captured output of one shell run, by line number.`
    - `grepHistory searches the captured output of this session's shell runs, line by line...`

    The words `test suite`, `build`, `script`, `delete`, `printed` and `log` stood nowhere in the nine-entry prefix. That is why "i want to run the project test suite now" answered `{"ids":[]}`: no candidate held a word of the query. And that is why "i need to see what the failing test printed" went to `files.read`, whose text says "reads a file's contents": the output of a command is not a file, and no description said so.

    Place 2 (the retrieval step) and place 3 (the preamble) needed no change. The prefix of this surface stands far under the budget (9,587 characters against 32,000), so every entry reaches the model in one prompt and no retrieval step selects between them. `FoundationModelsRanker` and `FoundationModelsMetadataRegistry` are unchanged, thus no card was written in either repository.
  timestamp: 2026-09-10T15:37:08.634500+00:00
- actor: claude-code
  id: 01m25zexb6vxcpycvd4dwbytv0
  text: |-
    ### what changed, and the measurements

    Each of the nine descriptions now opens with the work a person brings, and, where a verb was taking work it cannot do, says which verb does that work. Nothing was taken out of any description: every parameter sentence and every correction sentence stands as it stood.

    - `shell.execute`: names the test suite, one failing test, the build, a script, any other program; names version control (`git status`, `git diff`); names deleting, moving and copying a file or a whole directory.
    - `shell.getLines`: "shows what a command printed: the output of a run, the log it wrote, the report a failing test left behind. That output is not a file on disk, thus this verb reads it and the file verbs cannot."
    - `shell.grepHistory`: "finds a line in what the commands of this session printed — an error message, the name of a failing test, a warning."
    - `files.read`: names a file on disk, and says that what a command printed is not on disk.
    - `files.write`: names creating a file and replacing the whole contents of one, and says it never removes a file.
    - `files.edit`: says it changes a part of a file that already exists, and points a whole rewrite at write.
    - `files.patch`: names several files in one call, creating, deleting and renaming.
    - `files.glob`: names finding files by name, and points "which files you have changed" at `git status`.
    - `files.grep`: names finding a word inside files, and points "what you have changed" at `git status`.

    Measurements on `mlx-community/Qwen3-4B-4bit`, three rounds each.

    | suite | correct paths each round | undeclared paths each round | queries with no declared path |
    | --- | --- | --- | --- |
    | held-out, before | 9 of 22 | 8 | 6 of 15 |
    | held-out, after | 16 of 22 | 2 | 0 of 15 |
    | agent surface, before | 19 of 25 | 3 | 0 of 10 |
    | agent surface, after | 19 of 25 | 3 | 0 of 10 |

    The held-out level of 15 stands as it was written, and every held-out query now finds a declared path. The agent surface holds its level of 19 exactly, with the same three undeclared paths.

    The selection prefix grew from 7,600 to 9,587 characters, far under the budget of 32,000.

    Two intermediate readings, kept for the next agent:

    1. The first pass took the held-out rounds from 9 to 15 and left one query, "check which source files i have changed so far", answering `files.grep` and `files.glob`. The words "run a git command to see which files the checkout has changed" inside `shell.execute` were not enough on their own. What answered it was the boundary sentence on glob and on grep, which names `git status` through `tools.shell.execute`.
    2. The second pass then left "remove a scratch file i made earlier" answering `files.glob` and `files.write`. What answered it was the boundary sentence on write: "It never removes a file: tools.files.patch deletes one, and tools.shell.execute removes a file or a whole directory."

    The reading is that a description must say what the verb cannot do as well as what it does. A verb that is silent about a boundary takes work over that boundary.

    New unit suite `SelectionWordingTests` guards the wording. It builds the same nine-entry surface the two gated suites drive and holds each entry's `summaryBlock` to the everyday words for its work. It failed with 18 issues before the change and passes after it. It is the fast guard; the gated suite is the measurement.
  timestamp: 2026-09-10T15:37:25.606607+00:00
- actor: claude-code
  id: 01m25zf7dqmh2qq2bbr88z6gef
  text: |-
    ### implement — changed

    - evidence: cause — `APISurface.Entry.summaryBlock` gives the selection model the tool description alone (card `^0z0te3n`), and every description said what the verb does to its own data, never the work a person brings; the words "test suite", "build", "script", "printed" and "log" stood nowhere in the nine-entry prefix, thus the empty answer and the invisible shell verbs. Fix — a leading work sentence, and a boundary sentence where one verb was taking another's work, in all nine descriptions: `Sources/FoundationModelsMultitool/Capabilities/Shell/Execute.swift`, `GetLines.swift`, `GrepHistory.swift`, `Sources/FoundationModelsMultitool/Capabilities/Files/Read.swift`, `Write.swift`, `Edit.swift`, `Patch.swift`, `Glob.swift`, `Grep.swift`, plus the new guard `Tests/FoundationModelsMultitoolTests/SelectionWordingTests.swift`. Held-out counts, three rounds each: 9 of 22 correct with 8 undeclared and 6 queries answering nothing declared, before; 16 of 22 correct with 2 undeclared and 0 such queries, after. Agent surface: 19 of 25 with 3 undeclared, before and after, unchanged. `swift test` at the root: 1415 tests in 112 suites passed. `swift build --package-path IntegrationTests`: complete. `swift test --package-path IntegrationTests --no-parallel`: 24 tests in 17 suites passed, all three discovery suites among them; the one warning is SwiftPM's known `missing creator for mutated node` on the mlx-swift Cmlx bundle. No level lowered, no query changed, no package checkout edited.
    - next: review.
  timestamp: 2026-09-10T15:37:35.927923+00:00
depends_on:
- 01M25MFASNMHXXFCZEMKN9AY20
position_column: doing
position_ordinal: '8180'
title: The selection tier misses the shell verbs on held-out queries, and answers nothing for one of them
---
## What the held-out suite found

Card `^kn9ay20` added `HeldOutSurfaceDiscoveryTests`: fifteen queries written
from a task description alone, over the same nine-entry files-and-shell surface
and the same `agentFlashModel` (`mlx-community/Qwen3-4B-4bit`) as the ten
recorded queries of card `^zqz1zan`.

Measured 2026-09-10, three rounds, identical in every round:

- correct paths found: 9 of the 22 declared, each round.
- undeclared paths returned: 8, each round.
- six of the fifteen queries found no declared path at all, in every round.

The ten recorded queries scored 19 of 25 in the same runs. So the gap is not
the model and not the surface: it is the wording of the queries the tier was
never fitted to.

## The six queries that fail, and what the tier answered

| query | declared | answered |
| --- | --- | --- |
| rewrite the whole contents of a module | files.write, files.patch | files.edit |
| i want to run the project test suite now | shell.execute | nothing at all |
| i need to see what the failing test printed | shell.getLines, shell.grepHistory | files.read |
| delete a leftover temporary directory | shell.execute | files.glob, files.edit |
| remove a scratch file i made earlier | files.patch, shell.execute | files.glob, files.edit, files.write |
| check which source files i have changed so far | shell.execute | files.glob |

Two readings stand out.

**The empty answer is back.** "i want to run the project test suite now" gets
`{"ids":[]}` — the same failure card `^zqz1zan` records, on a query the
preamble was never fitted to. The preamble tells the model to prefer the
closest candidate over an empty answer, and on this wording it does not.

**The shell capability is nearly invisible.** Four of the six ask for a command
or for the output of one. `shell.getLines` and `shell.grepHistory` were never
selected one time in 45 calls. The tier answers a files verb for almost every
phrasing that does not carry the word "run" or "shell".

## What to do

Find why, and fix the cause rather than the six queries. The places to look:

1. The entry descriptions of `shell.execute`, `shell.getLines` and
   `shell.grepHistory`. They may say what the verb does and not what a person
   wants when they ask for it.
2. The retrieval step in front of the selection model, which decides which
   entries the model even reads.
3. The selection preamble, which card `^zqz1zan` chose against the ten
   recorded queries alone.

Do not lower `heldOutRoundCorrectLevel` and do not change a held-out query to
match what the tier answers. Both make the reading disappear rather than the
defect.

## The cause, found and fixed

Place 1 was the cause. Card `^0z0te3n` made `APISurface.Entry.summaryBlock` the
whole of what the selection model reads about a tool: the `// tools.<path>`
banner and the tool's `description`, with no parameter line and no signature.
Every description of this surface opens with what the verb does to its own
data — "execute starts one shell command in the background and answers at once
with its completion token" — and then gives its parameters. Not one of the nine
named the work a person brings.

- The empty answer: the words "test suite", "build" and "script" stood nowhere
  in the whole nine-entry prefix. A query whose only content word is "test
  suite" matched no candidate, so the model answered `{"ids":[]}`.
- The missing shell verbs: `getLines` and `grepHistory` were written around
  `commandID`, "captured output" and line numbers. A reader who wants to see
  what a command printed reads `files.read`, which says "reads a file's
  contents".

The fix gives each of the nine descriptions a leading sentence that names the
everyday work, and, where a verb was taking work it cannot do, a boundary
sentence that names the verb that can. No query was changed and no level was
lowered. Places 2 and 3 needed no change, thus no card in
`FoundationModelsRanker` or `FoundationModelsMetadataRegistry`.

## Acceptance Criteria

- [x] The cause of the empty answer for "i want to run the project test suite now" is named.
- [x] The cause of the missing shell verbs is named.
- [x] `HeldOutSurfaceDiscoveryTests` passes over three rounds, with no assertion made weaker.
- [x] `AgentSurfaceDiscoveryTests` still holds its own level of 19.

## Tests

- [x] `swift test --package-path IntegrationTests --no-parallel`, for both discovery suites.

#discovery #search-tools #selection-tier