---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m25tyx7spj9cfmhe28r3684j
  text: |-
    What the work found and did.

    - The surface. Four connected MCP servers of ten verbs each (issue tracker, database, observability, delivery pipeline), beside the files and shell capabilities, make 49 entries and a 34,181-character prefix against the 32,000-character budget. The tier splits that into 2 slices. The budget is untouched: the path is reached by a large surface through the mount a host really uses.
    - Where the verbs live. `Tests/Support/MCPTestServer/LargeCatalogToolKit.swift`, because that product is the one half both packages can share. A package cannot import another package's test target, so each of the two suites writes its own short `MultiTool.Builder` chain.
    - The order rule needs no change in the ranker. `SelectionTier.selectFromEveryRun` merges the answers slice by slice in catalog order, `matches(forIDs:limit:)` keeps the first place of a repeated id and cuts to the limit, and `MetadataSearcher.selectionSearch` maps the matches one for one with no re-sort. So catalog order between slices, model order inside a slice, is what the code does today. No card was written in the ranker repository.
    - The score cannot order the result. A match is scored `1 / rank` inside its own slice, so the first pick of every slice scores `1.0`. The unit test makes each slice answer its own last id before its own first id, which no score sort and no catalog-position sort can produce.
    - Why the order test is a unit test. It needs no model, it runs in 0.1 s, and it holds the rule over the same real above-budget surface. The gated suite holds what only a live model can show.
    - A stale sentence was corrected. `SearchToolsTool.makeSelection` still said the tier "selects among the top-M candidates" over budget. The tier cuts nothing since ranker card `^kqp9e5e`; the comment now says it prompts one slice at a time.
    - The banner reader and the `RESULT` printer moved to `IntegrationTests/.../Support/CatalogFeedback.swift`, so the two gated suites read the same one. `AgentSurfaceDiscoveryTests` keeps its own label and its counts did not move.
  timestamp: 2026-09-10T14:18:46.905839+00:00
- actor: claude-code
  id: 01m25tz57yxwkv40shtvhh7190
  text: |-
    ### implement — changed
    - evidence: 6 files — Tests/Support/MCPTestServer/LargeCatalogToolKit.swift (new, 40 verbs on 4 servers), Tests/FoundationModelsMultitoolTests/OverBudgetSelectionOrderTests.swift (new, 4 tests), IntegrationTests/.../OverBudgetSurfaceDiscoveryTests.swift (new, 1 gated test), IntegrationTests/.../Support/CatalogFeedback.swift (new, shared readers), Sources/FoundationModelsMultitool/Discovery/SearchToolsTool.swift (the order rule in the doc comment of format(task:matches:sample:)), IntegrationTests/.../AgentSurfaceDiscoveryTests.swift and Support/LiveRouterFixture.swift (use the shared readers; name the new suite as a taker of the plumbing probe model). The large surface: 49 entries, 34,181 characters, budget 32,000, 2 slices, elapsed 2.949 s and 1.292 s. Runs: `swift test` 1,414 tests in 111 suites passed; `swift build --package-path IntegrationTests` complete; the new gated suite passed in 7.156 s; AgentSurfaceDiscoveryTests passed in 10.124 s with 9 entries and 7,601 characters.
    - next: review
  timestamp: 2026-09-10T14:18:55.102305+00:00
depends_on:
- 01M25KGJZVPVF5XW0WQ46J5HQW
position_column: doing
position_ordinal: '80'
title: searchTools has no test above the selection budget, where the ranker splits the catalog into slices
---
## What happened

`AgentSurfaceDiscoveryTests` is the only live test of discovery. It builds a surface of 9 entries. Every run of it stays under the selection budget. So the test exercises one of the two paths of `SelectionTier.search(intent:limit:)`, and never the other.

| measure | value |
|---|---|
| budget (`SelectionConfig.defaultCapacityCharacterLimit`) | 32,000 characters |
| the tested surface | 7,600 characters, 9 entries |
| per-entry size on that surface | 527 to 1,576 characters |
| entries before the surface crosses the budget | about 20 to 40 |

The range is what matters, not the average. A surface of tools with long descriptions crosses at about twenty entries.

## Why this package must test it

**The trigger is a feature of this package.** `MCPCapability` mounts every verb of every connected server, each under the name of its own server. To add servers is the purpose of that feature. Two ordinary servers, with the files and shell verbs, reach twenty entries.

**The surface changes while a session runs.** `SurfaceRefresher` rebuilds the registry when a server changes its list of tools, and `MultiTool.turnWillBegin()` swaps the new registry in at the next turn boundary. So a session can cross the budget in the middle of its own work. No person selects that moment.

**The code on the other side is new.** Ranker commit `aac493a` (card `^kqp9e5e`, 2026-09-10) rewrote the over-budget path. The old path ranked the catalog and cut it to the top candidates. The new path (`SelectionTier.swift:96-108`) splits every id, in catalog order, into runs that each fit the budget, and prompts each run. Every id now reaches a prompt. But each id is judged in its own slice, with no other slice present. A slice that holds no good answer gets the same question as the slice that holds the correct one, and it answers alone.

**The descriptions-only change made this less visible, not less real.** Card `^0z0te3n` moved the prefix from 17,263 characters to 7,600. That doubled the headroom. More tools are now necessary to cross the budget, so the first person to cross it is the person with the most servers, not a developer.

## The two failures that belong to this package

**Match order is unspecified across slices.** The new tier scores a match by its position in its own slice: `orderScore(rank:) = 1.0 / Double(rank)` (`SelectionTier.swift:399-401`). A first-place match in slice three carries the same score as a first-place match in slice one. `SearchToolsTool.format(task:matches:sample:)` splices the blocks in the order it receives them, and the model reaches for the first tool it reads. Nothing in this package states what that order must be when the matches come from more than one slice.

**Latency grows with the size of the catalog.** Over the budget, `searchTools` makes one model call for each slice, not one call in total. `searchTools` blocks. A large surface makes discovery several times slower, and no test and no log line reports it.

## What to do

1. Add a gated test that builds a surface above the budget. Do not invent a new mount path. Use the MCP capability with a stub server that declares many verbs, or mount enough demo tools, so the surface is the shape a host really builds. Print the entry count and the prefix size, as `AgentSurfaceDiscoveryTests` does.
2. Assert what this package owns. Every match that comes back is spliced one time. No id is repeated. The count of matches obeys the limit. The result is usable by the model.
3. Decide and state the order rule for matches that come from more than one slice. Write the rule in the doc comment of `SearchToolsTool.format(task:matches:sample:)`, and hold it with a test. If the correct rule needs a change in the ranker, do not edit the checkout. Write a card in the ranker repository and name it here.
4. Print the elapsed time of each `searchTools` call, and the number of slices. Do not assert on time. A reading that a person can read is enough.
5. Keep the run short. The suite is gated and uses a live model. One surface above the budget is enough. Do not add a second one.

## Rules

- Do not edit a package checkout under `.build/checkouts`.
- Do not lower the budget to force the path. A test that changes the budget tests the test. Build a real surface that is large.
- Do not delete a test to make this one green.

## The order rule, as decided

The rule is written on `SearchToolsTool.format(task:matches:sample:)`. It is what the code already does, so no change in `FoundationModelsRanker` is necessary and no card was written there.

1. Under the budget: the order the selection model answered in, over the whole catalog.
2. Over the budget: slice by slice in catalog order, and inside each slice the order that slice's model answered in. A match from an earlier slice stands above a match from a later one.
3. Either way: an id the model repeats keeps its first place and is spliced one time, and the list is cut to the limit after every slice has answered.

The score cannot be the order key: a match is scored `1 / rank` inside its own slice, so the first pick of every slice scores `1.0`. `MetadataSearcher` maps the tier's matches one for one and never re-sorts them.

## Acceptance Criteria

- [x] A gated test builds a surface above 32,000 characters and states its entry count and prefix size on this card. `OverBudgetSurfaceDiscoveryTests`: entries=49, prefixCharacters=34,181, budget=32,000, slices=2 for each call.
- [x] The test proves every match is spliced one time, with no repeated id, inside the limit.
- [x] The order rule for matches from more than one slice is written in a doc comment and held by a test. `OverBudgetSelectionOrderTests` holds it over the same size of surface with a scripted model.
- [x] The elapsed time and the slice count of each call are printed. Measured: 2.949 s and 1.292 s, two slices each.
- [x] `AgentSurfaceDiscoveryTests` still passes, with its counts on this card. entries=9, prefixCharacters=7,601, ten queries answered, queries 4 to 9 each held.

## Tests

- [x] `swift test` at the root: no failure, no warning. 1,414 tests in 111 suites passed.
- [x] `swift test --package-path IntegrationTests --no-parallel`, for the new suite and for `AgentSurfaceDiscoveryTests`. Both passed.

#discovery #search-tools #test-coverage