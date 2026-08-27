---
assignees:
- claude-code
depends_on:
- 01M112EG33CSGN466M9BHVD8C0
position_column: todo
position_ordinal: 8c80
title: 'Make the Builder re-runnable: rebuild a Registry from the same configuration'
---
## What
The first half of rebuild-and-swap. eventplan.md § "Consolidation of the siblings": "A late server, a reconnect, or an MCP `tools/list_changed` starts a full rebuild. MultiTool renders the new registry complete at the side." Today `MultiTool.Builder` is consumed one time. Make the same configuration able to give a new `Registry` on request.

- Modify `Sources/FoundationModelsMultitool/Surface/MultiToolBuilder.swift`: keep the recorded items (`standalone`, `grouped`, capabilities) as the builder's value, and add `public func rebuildRegistry() async throws -> MultiTool.Registry`. For each `MCPCapability`, it reads the server's current catalog again and makes new `MCPTool` verbs. For each other capability and tool, it reuses the same instances. Then it runs the same `buildRegistry()` validation (nouns, verbs, duplicates).
- Add `public var registrySource: RegistrySource` or an equivalent `Sendable` value that a session keeps after `build()`: the recorded items, and nothing else. `rebuildRegistry()` is a method of that value, so a host does not keep the Builder itself.
- The rebuild never mutates a `Registry`. `Registry` stays a `let`-only value. eventplan.md: "The surface never changes in place."
- Keep `build()` and `buildRegistry()` as they are. The one-time path does not change.

## Acceptance Criteria
- [ ] `rebuildRegistry()` after a `ScriptedServer` adds a tool gives a `Registry` with the new verb, and the first `Registry` value is unchanged.
- [ ] `rebuildRegistry()` after a server removes a tool gives a `Registry` without it.
- [ ] A rebuild that would now collide (a server tool renamed to an illegal verb) throws `MultiToolBuilderError`, and the caller keeps the old `Registry`.
- [ ] Shell and files verbs are the same instances across a rebuild (identity of the `ShellState` store holds).
- [ ] `swift build` succeeds.

## Tests
- [ ] Add `Tests/FoundationModelsMultitoolTests/RegistryRebuildTests.swift` with the criteria above, over `DynamicToolsetScenario` from the test server.
- [ ] `swift test --filter RegistryRebuildTests` passes.
- [ ] `swift test --filter CapabilityRegistrationTests` still passes.

## Workflow
- Use `/tdd` — write the rebuild tests first, then implement. #eventplan #phase-4