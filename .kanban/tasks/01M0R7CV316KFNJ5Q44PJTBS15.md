---
assignees:
- claude-code
position_column: todo
position_ordinal: '9280'
title: Make withCapability(_:) claim ownership of its noun
---
## What

eventplan.md § "Registration of capabilities: noun/verb" says:

> Nouns are unique. Registration rejects a duplicate noun. An MCP server with
> the name `files`, against the files capability, fails loudly at
> `buildRegistry()`. It does not fail silently at dispatch.

The example in that text is a collision of the **noun only**. The verbs of an
MCP server and the verbs of the files capability are different.

`buildRegistry()` does not do this today. It rejects a duplicate
`<noun>.<verb>` path, and it rejects a noun that collides with a flat tool
name. Two capabilities that give the same noun with different verbs merge into
one namespace. They do not fail. So the example that eventplan.md gives does
not fail loudly today.

This task closes that gap. It comes from the review of
`^sfh0v2p` (Add the Capability protocol and Builder.withCapability(_:)), where a
person decided to keep the acceptance criterion of that task narrow and to move
the ownership of the noun here.

## Design

Ownership of the noun belongs to `withCapability(_:)`, not to
`register(noun:tool:)` and not to `addGroup(named:_:)`. This distinction is
necessary:

- `addGroup(named:_:)` documents a **merge**. Two calls with one group name put
  their tools in one namespace. Tests that exist depend on this. Do not change
  it.
- `withCapability(_:)` **claims** a noun. A capability owns its whole noun. A
  second capability that claims a noun that another capability owns is the
  error that eventplan.md describes.

Suggested shape in
`Sources/FoundationModelsMultitool/Surface/MultiToolBuilder.swift`:

- Keep a set of the nouns that capabilities claim, with the source of each
  claim, in the `Builder`.
- `withCapability(_:)` records the claim, and then calls
  `register(noun:tool:)` for each tool as it does now.
- `buildRegistry()` fails when one noun has two claims, and when a claimed noun
  also holds a tool that came from `addGroup(named:_:)` or from `addTool`.
- Give `MultiToolBuilderError.Kind` a new case for this error, or state clearly
  in the doc comment why an existing case is correct. The message must name the
  noun and both sources, so the failure is loud.

## Acceptance Criteria

- [ ] Two capabilities that declare the same noun and **different** verbs fail
      at `buildRegistry()` with `MultiToolBuilderError`.
- [ ] The error message names the noun and both capabilities.
- [ ] A capability and an `addGroup(named:_:)` call that use one noun fail at
      `buildRegistry()`.
- [ ] Two `addGroup(named:_:)` calls with one group name keep their merge. No
      test that exists changes.
- [ ] `addTool` keeps its behavior.
- [ ] Each new or changed public declaration has a doc comment.

## Tests

- [ ] Add to `Tests/FoundationModelsMultitoolTests/CapabilityRegistrationTests.swift`:
      two capabilities with noun `"demo"` and different verbs throw at
      `buildRegistry()`.
- [ ] Same file: a capability with noun `"demo"` and an `addGroup(named: "demo")`
      call throw at `buildRegistry()`.
- [ ] Same file: the eventplan.md example — a capability named `files` and a
      second registration named `files` — fails at `buildRegistry()`.
- [ ] A test that proves two `addGroup(named:_:)` calls with one name still
      merge.
- [ ] `swift test` passes with no new failure and no new warning.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #phase-2 #eventplan