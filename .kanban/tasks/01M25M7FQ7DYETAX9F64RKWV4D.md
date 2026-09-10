---
assignees:
- claude-code
depends_on:
- 01M25KGJZVPVF5XW0WQ46J5HQW
position_column: todo
position_ordinal: '8180'
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

## Acceptance Criteria

- [ ] A gated test builds a surface above 32,000 characters and states its entry count and prefix size on this card.
- [ ] The test proves every match is spliced one time, with no repeated id, inside the limit.
- [ ] The order rule for matches from more than one slice is written in a doc comment and held by a test.
- [ ] The elapsed time and the slice count of each call are printed.
- [ ] `AgentSurfaceDiscoveryTests` still passes, with its counts on this card.

## Tests

- [ ] `swift test` at the root: no failure, no warning.
- [ ] `swift test --package-path IntegrationTests --no-parallel`, for the new suite and for `AgentSurfaceDiscoveryTests`.

#discovery #search-tools #test-coverage