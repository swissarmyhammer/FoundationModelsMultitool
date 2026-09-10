---
assignees:
- claude-code
depends_on:
- 01M25KGJZVPVF5XW0WQ46J5HQW
position_column: todo
position_ordinal: '8280'
title: The gated discovery suite is graded on the ten queries its own preamble was chosen with
---
## What happened

`IntegrationTests/.../AgentSurfaceDiscoveryTests.swift` holds ten queries. Those ten queries come from one `acp-agent` run of `astropy__astropy-12907`, recorded on card `^zqz1zan`.

The preamble of card `^zqz1zan` was selected by measurement against those same ten queries. Card `^zqz1zan` records the table: wording V0 answered 2 of 10, and wordings V2 to V5 answered 10 of 10. The wording that won is now the code, and the ten queries that chose it are now the test.

So the suite grades the answer against its own answer key. It shows that the wording works for the queries that selected it. It shows nothing about a query nobody has seen.

## Two more limits of the same suite

**One round.** The suite makes one pass of the ten queries. A 4B model is stochastic. Between two recorded runs, query 9 answered five matches and then six matches. Nothing observed that. A change that makes the model answer eight of ten can pass or fail by chance.

**A floor, not a level.** The suite asserts that queries 4 to 9 each answer at least one match, and that one match is the write verb, the edit verb or the shell verb. A run that answered with all nine tools for every query passes that test. Precision is not measured, so it can fall to nothing without a failure.

## What to do

1. Write a set of held-out queries. Write them without reading the names of the tools of the surface. A person can write them, or a larger model can write them from a task description alone. Ten to twenty queries are enough. Record how they were written on this card, because that record is the value of the set.
2. Keep the ten queries of `^zqz1zan` as a separate group. They are a regression record of a real failure. Do not mix the two groups, and report them apart.
3. Run each group three rounds. Report the count of answers for each round.
4. Grade a level, not only a floor. For each query, record which tools the surface holds that a person says are correct. Report how many correct tools the run found, and how many wrong tools it returned. Assert on the count of correct tools. Print the count of wrong tools without asserting on it, until a level is known.
5. Keep the run short. The suite is gated and uses a live model. Say on this card how long the new suite takes.

## Rules

- Do not write a held-out query by reading the tool names. That repeats the fault this card names.
- Do not delete the ten queries of `^zqz1zan`.
- Do not make an assertion weaker to make a run green.

## Acceptance Criteria

- [ ] A held-out query set is in the suite, and this card records how it was written.
- [ ] The two groups are reported apart.
- [ ] Each group runs three rounds, and the counts of each round are on this card.
- [ ] The correct tools of each query are declared, and the suite asserts on the count found.
- [ ] The count of wrong tools is printed for each query.
- [ ] This card states the run time of the new suite.

## Tests

- [ ] `swift test --package-path IntegrationTests --no-parallel`, for the new suite and for `AgentSurfaceDiscoveryTests`.

#discovery #search-tools #test-coverage