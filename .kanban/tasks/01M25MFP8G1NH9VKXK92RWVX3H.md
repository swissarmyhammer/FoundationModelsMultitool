---
assignees:
- claude-code
depends_on:
- 01M25KGJZVPVF5XW0WQ46J5HQW
position_column: todo
position_ordinal: '8380'
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

- [ ] A gated test drives `UnknownToolHint` on a live surface with an embedder.
- [ ] The three shapes of wrong path each have a case.
- [ ] The test asserts that every named tool exists on the surface.
- [ ] The tier and the named tools are printed for each case.

## Tests

- [ ] `swift test` at the root: no failure, no warning.
- [ ] `swift test --package-path IntegrationTests --no-parallel` for the new suite.

#discovery #search-tools #test-coverage