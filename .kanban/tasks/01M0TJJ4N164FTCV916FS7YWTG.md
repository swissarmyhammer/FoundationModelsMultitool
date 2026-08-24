---
assignees:
- claude-code
position_column: todo
position_ordinal: '9580'
title: Derive the "verb noun" journal op at registration
---
## What

eventplan.md § "Registration of capabilities: noun/verb" states:

> `OperationEvent.op` stays the canonical `"verb noun"` string. Registration
> derives it as `"\(verb) \(noun)"`. As a result, Router renders the journal and
> the outbox without change.

**That derivation is not implemented.** Nothing in `Sources/` builds a
`"verb noun"` string. Router's `ToolContext.init(stamping:)` stamps BOTH `tool`
and `op` with `tool.name`, so today a `tools.shell.execute` run journals its
`op` as `"execute"` and never `"execute shell"`.

**A verb cannot fix this for itself.** `ToolContext.post(_:)` re-stamps every
event it forwards: only `kind`, `detail`, `outcome` and `elicitation` survive,
and `tool`, `op` and `correlationID` come from the context. So a verb that built
its own `OperationEvent` with `op: "execute shell"` has that value overwritten.
A verb also does not know its own noun — `register(noun:tool:)` supplies the
noun, and `Tool.name` supplies only the verb.

The work therefore belongs at the registration site, which is the one place both
halves of the pair stand together:
`Sources/FoundationModelsMultitool/Surface/MultiToolBuilder.swift`
(`register(noun:tool:)`, `withCapability(_:)`, `addGroup(named:_:)`).

## Where it came from

Card `^bwv86sy` ("Add the `tools.shell.execute` verb") states in its `## What`
that "the journal `op` is `"execute shell"`". Every other bullet of that card
landed; this one could not, for the reason above. It is recorded here rather
than left as a silent gap.

## Acceptance Criteria

- [ ] A tool registered under noun `shell` with `Tool.name` `execute` journals
      its `OperationEvent.op` as `"execute shell"`.
- [ ] `tools.<noun>.<verb>` on the surface and `"verb noun"` in the journal come
      from the one pair, and no site spells either one again.
- [ ] The `tool` field keeps naming the tool, and only `op` carries the pair.
- [ ] A tool registered with no noun keeps its current `op`, so nothing that
      renders today changes shape.

## Tests

- [ ] A test registers a verb under a noun, runs it, and asserts the recorded
      event's `op`.
- [ ] A test asserts the surface path and the journal `op` are derived from the
      same noun/verb pair.
- [ ] `swift test` passes with no new failure and no new warning.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #phase-2 #eventplan