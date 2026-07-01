---
depends_on:
- 01KWFNVC3SA55SBZMCCWW6994C
position_column: todo
position_ordinal: 8a80
title: 'M7: In-snippet help() / docs() globals'
---
## What
Per plan.md M7: in-language introspection backed by the same `APISurface` (one source of truth with the librarian prefix and findAPIs).
- Extend the interpreter installation in `MultiTool.swift`: inject `help()` → array of available function names (grouped layout shown per plan Resolved #5), and `docs(name)` → that tool's full rendered block (signature + doc + example); unknown name → helpful error listing close matches.
- These are the only extra globals; the deny-by-default sandbox is otherwise unchanged.

## Acceptance Criteria
- [ ] `runCode("return help()")` returns all names incl. `group.name` entries
- [ ] `runCode("return docs('weather')")` returns the exact rendered block from the surface
- [ ] `docs('nope')` returns an error message naming near-matches, not a crash
- [ ] Sandbox check: no other new globals are reachable

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/HelpDocsTests.swift` — the four criteria above against a fixture surface
- [ ] `swift test --filter HelpDocsTests` → passes

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.