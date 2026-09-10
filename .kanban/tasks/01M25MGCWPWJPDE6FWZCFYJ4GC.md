---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m26k19s2scf2pggjq28hgh80
  text: |-
    ### Step 1 — the measurement

    Measured on 2026-09-10 with a temporary test over two surfaces. The test built each surface through the production chain and read `entry.block.count`, `entry.summaryBlock.count` and `entry.descriptor.description.count`. The test is removed again; the numbers stand here and in the doc comment of `APISurface.Entry.summaryDescriptionCharacterLimit`.

    **The native nine-entry files-and-shell surface** (`withFiles(root:readOnly:false)` and `withShell(storeDirectory:)`):

    | path | block | summaryBlock | description |
    |---|---|---|---|
    | files.read | 1838 | 860 | 840 |
    | files.write | 1498 | 811 | 790 |
    | files.edit | 2411 | 973 | 953 |
    | files.patch | 2487 | 1684 | 1663 |
    | files.glob | 2011 | 838 | 818 |
    | files.grep | 2916 | 1094 | 1074 |
    | shell.execute | 2164 | 1372 | 1349 |
    | shell.getLines | 1551 | 706 | 682 |
    | shell.grepHistory | 1844 | 719 | 692 |
    | **total (9)** | **18720** | **9057** | — |

    **The three-verb loopback MCP surface** (`withMCP(servers:)` over the scripted server):

    | path | block | summaryBlock | description |
    |---|---|---|---|
    | loopback.echo | 288 | 62 | 39 |
    | loopback.elicitEcho | 230 | 76 | 47 |
    | loopback.elicitURL | 237 | 85 | 57 |
    | **total (3)** | **755** | **223** | — |

    What the numbers say:

    - A `summaryBlock` is the banner plus the description. The banner is 21 characters at most on these two surfaces, thus the description is nearly the whole of the selection prompt.
    - The longest description this package writes is `files.patch` at 1663 characters. A cap must stand above it, or the wording that `SelectionWordingTests` holds goes away.
    - An MCP description is 39 to 57 characters here, because the scripted server is small. Nothing limits it: the size comes from the server.
  timestamp: 2026-09-10T21:19:31.106797+00:00
- actor: claude-code
  id: 01m26khxacv73vyv3kp0f1pc0s
  text: |-
    ### implement — changed

    - evidence: 5 files. `Sources/FoundationModelsMultitool/Surface/APISurface.swift` (the cap, the empty-description sentence, and the rule in the doc comment of `summaryBlock`); `Tests/FoundationModelsMultitoolTests/SummaryBlockCapTests.swift` (7 unit tests, new); `Tests/Support/MCPTestServer/LargeCatalogToolKit.swift` and `LargeCatalogSurface.swift` (a `describing:` flag and a `domains:` list, both with defaults, so the two suites that read the mount are unchanged); `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/NoDescriptionSurfaceDiscoveryTests.swift` (the gated run, new).

      **The measurement.** Native surface: description 682 to 1663 characters, `summaryBlock` 706 to 1684, `block` 1498 to 2916, nine entries. MCP loopback surface: description 39 to 57, `summaryBlock` 62 to 85, `block` 230 to 288, three entries. The full table stands in the comment above.

      **The cap.** `APISurface.Entry.summaryDescriptionCharacterLimit = 2000`, and the cut stands in `APISurface`, thus a native tool obeys it too. 2000 stands over the longest description this package writes (`files.patch`, 1663) with room for about a fifth more, so no shipped description is cut and `SelectionWordingTests` is untouched. The cut keeps the head back to the last space and closes with a `[cut <n> characters]` line of its own; room for that line is reserved against the largest count it could name, thus the text never goes over the cap.

      **An empty description.** The summary now reads `<verb> takes <argument names>.` — `run_query takes connection, sql and parameters.` A verb with no argument reads `<verb> takes no argument.` A description of spaces alone counts as no description.

      **What the flash model picks, before and after.** 3 rounds of 3 queries over a 19-entry surface (files, shell, and a database server of ten verbs that publish no description), on the flash slot of `plumbingProbeProfile`. Only the entries with no description change between the readings; a described entry keeps its own text, so the three readings differ in one text alone. Correct/wrong paths over the whole run: banner alone 3/33; the name of the tool alone 3/39; the argument-name sentence 6/45. The sentence doubles the correct count and it answers 2 of 3 queries each round where the other two answer 1, so the card keeps it.

      Tests: `swift test` at the root — 1422 tests in 113 suites passed, no failure, no warning. `swift build --package-path IntegrationTests` — Build complete. Gated: `AgentSurfaceDiscoveryTests` 1 test passed, 19 correct and 3 wrong in each of 3 rounds of 10 queries; `NoDescriptionSurfaceDiscoveryTests` 1 test passed; `OverBudgetSurfaceDiscoveryTests` 1 test passed; `HeldOutSurfaceDiscoveryTests` 1 test passed; `UnknownToolHintLiveTests` 1 test passed.

    - next: review.

    **Two notes for the next agent.**

    1. The first reading of the gated run was wrong, and the numbers it gave (banner 0, name 6, arguments 6) must not be read. It rewrote the summary of EVERY entry under each candidate, thus the described files and shell entries were measured beside the empty ones. `NoDescriptionCandidate.summaryBlock(of:)` now changes an entry with no description alone.
    2. `agentFlashModel` carries a written rule that no other suite may take it, so the new gated suite reads the flash slot of `plumbingProbeProfile`. The card asks for "the flash model"; this is a flash slot, but it is not the agent's pinned 4B.
  timestamp: 2026-09-10T21:28:35.404266+00:00
- actor: claude-code
  id: 01m26kqqh4sq5y3snnehasnj61
  text: |-
    ### commit — changed
    - evidence: efb84b5 — 9 files changed, 685 insertions(+), 19 deletions(-)
    - next: send the task on to the review step.
  timestamp: 2026-09-10T21:31:46.084834+00:00
- actor: claude-code
  id: 01m26mbtbgvp62vy383dgge8bv
  text: |-
    ### review — findings
    - evidence: 2 findings over HEAD~1..HEAD — IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/NoDescriptionSurfaceDiscoveryTests.swift:178, IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/NoDescriptionSurfaceDiscoveryTests.swift:231. Both are the rule swift/immutability on the new gated suite.
    - next: Build the dictionary and the array without a var accumulator. Remove that cause from the full file, then run the review again.
  timestamp: 2026-09-10T21:42:44.336231+00:00
- actor: claude-code
  id: 01m26mcezfacy8zm86hx31ykgd
  text: |-
    ### finish iteration 1 — findings

    - implement: changed. The cap stands in `APISurface`, thus a native tool obeys it too. The limit is 2000 characters, over the longest description this package writes, which is 1663. An empty description now gives the verb name and its argument names. The measured sizes are on this card.
    - test: green. `swift test` gives 1422 pass in 113 suites. `swift build --package-path IntegrationTests` gives 0 error. The gated discovery suites pass. The new gated suite shows the argument-name text gives 2 correct per round, where the banner alone gives 1.
    - commit: efb84b5, 9 files.
    - review: findings. 2 open findings over `HEAD~1..HEAD`, both `swift/immutability`, both in the new file `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/NoDescriptionSurfaceDiscoveryTests.swift`, at line 178 and line 231. Each builds a collection with a `var` accumulator in a loop.
  timestamp: 2026-09-10T21:43:05.455962+00:00
- actor: claude-code
  id: 01m26mkmmwjdq72j6t0g4knxbj
  text: |
    ### implement — changed

    - evidence: 1 file — `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/NoDescriptionSurfaceDiscoveryTests.swift`. The rule `swift/immutability` stood in three places of that file, and not only in the two the review named: the `totals` dictionary of the test body, the `grades` array of the round loop, and the `total` tuple that the round loop added to. All three are gone. A new fileprivate `Sequence.mappedInOrder(_:)` maps with an asynchronous transform, one element at a time and in sequence order, because `map` takes no asynchronous transform and a task group would run the model calls together. It walks the head and then the tail and joins the two answers, thus it builds the array and never mutates an empty one. The dictionary is now `Dictionary(uniqueKeysWithValues:)` over the mapped `(candidate, total)` pairs. The round is now `DiscoveryRound`, the same type the other gated discovery suites read, and its `correctCount` and `wrongCount` give the same two numbers the local tuple gave. No test was removed, no assertion was made weaker, and no production source was changed.

      Tests: `swift test` at the root — 1422 tests in 113 suites passed, no failure, no warning. `swift build --package-path IntegrationTests` — Build complete. `swift test --package-path IntegrationTests --no-parallel --filter NoDescriptionSurfaceDiscoveryTests` — 1 test in 1 suite passed in 33.5 s, with the same counts as before: banner=3/33, name=3/39, arguments=6/45, which is 1 correct per round for the banner text, 1 for the name text and 2 for the argument text. The only message in the output is the known SwiftPM line about the mlx-swift Cmlx bundle.

    - next: review.
  timestamp: 2026-09-10T21:47:00.636888+00:00
position_column: doing
position_ordinal: '80'
title: An MCP tool description goes into the selection prompt with no cap, and an empty one makes the tool unpickable
---
## What happened

An MCP tool is an ordinary `Tool`, so it goes down the same render path as a native tool (`Capabilities/MCP/MCPTool.swift:57`). Three of its fields come from the server:

```
79:    var name: String { entry.name }
83:    var description: String { entry.description }   // verbatim, "" when the server gives none
88:    var parameters: GenerationSchema { entry.parameters }
```

Card `^0z0te3n` made the selection prompt hold the description of each tool and nothing else (`APISurface.swift:110-112`). So for an MCP tool, the selection prompt now holds text that a third-party server controls, word for word.

Two defects follow.

**No cap.** No file of this package limits the length of an MCP tool description. `RenderBudget` (`Capabilities/MCP/RenderBudget.swift:48-81`) caps the text of a `tools/call` RESULT only. Nothing under `Sources/FoundationModelsMultitool/Surface/` limits a description. A server that declares forty tools, each with a description of some thousands of characters, makes a selection prefix of some tens of thousands of characters. The ranker then splits that prefix into slices and makes one model call for each slice. The size of the prompt, the number of model calls and the time of a `searchTools` call are all set by the server.

**An empty description hides the tool.** When a server gives no description, `entry.description` is the empty string. Then `summaryBlock` is the banner and nothing else. The selection model sees `## <server>.<tool>` with no words under it, and it must choose from a name alone. The tool is still in the retrieval index, because `renderBlock()` holds the rendered parameters. So the tool is findable by keyword and near-invisible to selection. Before card `^0z0te3n` the block carried the parameter lines, and those words gave the model something to read.

## What to do

1. Measure first. Build a surface over the scripted MCP server (`Tests/FoundationModelsMultitoolTests/MCPCapabilityTests.swift:159-227` already builds one) and record the size of `block` and of `summaryBlock`, for an MCP tool and for a native tool. Put the numbers on this card. No such measurement exists today.
2. Give a description a cap. Put the cap where the surface is rendered, not in the MCP capability, so a native tool with a long description obeys the same rule. Cut on a word boundary and make the cut visible to a reader.
3. Choose what the summary holds when a description is empty. Two candidates: the name of the tool alone, or the names of the parameters. Measure both on the flash model over a surface of tools with no description, and keep the one the model picks better.
4. State the rule in the doc comment of `APISurface.summaryBlock`.

## Rules

- Do not cap a description inside `MCPTool`. That hides the rule from a native tool.
- Do not remove the empty-description case by refusing the tool. A server is permitted to give no description, and the tool must stay callable.
- Do not edit a package checkout under `.build/checkouts`.

## Acceptance Criteria

- [x] The sizes of `block` and `summaryBlock` for an MCP tool and for a native tool are on this card.
- [x] A description over the cap is cut, and a unit test holds the cap.
- [x] A tool with no description gets a summary that holds more than its banner, and a unit test holds it.
- [x] The rule is in the doc comment of `APISurface.summaryBlock`.
- [x] A gated run over a surface of tools with no description records what the flash model picks, before and after.

## Tests

- [x] `swift test` at the root: no failure, no warning.
- [x] `swift test --package-path IntegrationTests --no-parallel --filter AgentSurfaceDiscoveryTests`: passes, with counts on this card.

## Review Findings (2026-09-10 17:32)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 5 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/NoDescriptionSurfaceDiscoveryTests.swift:178` `swift/immutability` — Building a dictionary via a var accumulator in a loop. Mutable collection should be built functionally with map/compactMap or similar, not by initializing an empty collection and mutating it in a loop. Refactor to build the dictionary functionally, possibly by collecting (candidate, result) pairs and converting with Dictionary(uniqueKeysWithValues:), once async/await patterns allow.
- [x] `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/NoDescriptionSurfaceDiscoveryTests.swift:231` `swift/immutability` — Building an array via a var accumulator in a loop. Mutable collection should be built functionally with map/compactMap or similar, not by initializing an empty collection and appending to it in a loop. Refactor to build the array functionally, such as by collecting grades first and then performing side effects, or by using map/flatMap if async composition can be achieved.
#discovery #search-tools #mcp #defect