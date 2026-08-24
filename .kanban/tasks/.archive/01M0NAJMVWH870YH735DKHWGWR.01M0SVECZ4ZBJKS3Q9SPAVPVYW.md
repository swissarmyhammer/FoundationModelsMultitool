---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0svdj7d3b3bxb42tth57065
  text: |-
    ### Cancelled by decision 2026-08-24 — there is no ask outcome to route

    The shell capability asks no permission question, thus nothing routes into
    `ToolContext.elicit` from the policy path. `ShellPolicy` itself is cancelled
    (`^j5mrn00`).

    `elicit()` and the MCP elicitation passthrough are NOT cancelled and are not
    touched. They are the general capability for a question in the middle of a run —
    `await elicit("Which repository should I target?")` — and the MCP spec envelope
    with `accept` / `decline` / `cancel` and URL mode. Only the shell permission use
    of them goes away.
  timestamp: 2026-08-24T12:20:12.141413+00:00
depends_on: []
position_column: todo
position_ordinal: '8980'
title: Route the ask policy outcome through ToolContext.elicit
---
## What

eventplan.md § "Consolidation of the siblings": *"Today it refuses, because the
tool cannot speak to a human. With elicitation always available, ask goes
through `ToolContext.elicit`, and the remembered-"always" store works as
designed."*

Make the `ask` outcome a question to the person.

- Add `Sources/FoundationModelsMultitool/Capabilities/Shell/ShellAsk.swift`.
- On an `ask` decision, read `ToolContext.current`. Build an
  `ElicitationRequest` in form mode with a single-select schema. The choices
  are: allow one time, always allow, deny one time, always deny.
- `await context.elicit(request)`. Process the three actions of
  `ElicitationResponse`:
  - `accept` — apply the chosen answer. Write "always allow" and "always deny"
    into `ShellDecisionStore`.
  - `decline` — the command does not run. This is a refusal, not a cancelled
    run.
  - `cancel` — the command does not run, and the run reports cancellation.
- When `ToolContext.current` is `nil`, keep the behavior that exists: refuse.
  A tool with no host cannot ask.
- The elicitation schema must obey the restricted subset that
  `ElicitationRequestedSchema` enforces — a flat object with primitive
  properties only.

## Acceptance Criteria

- [ ] An `ask` decision under a bound `ToolContext` sends exactly one
      `ElicitationRequest`.
- [ ] An `accept` of "allow one time" runs the command, and it writes nothing
      into the decision store.
- [ ] An `accept` of "always allow" runs the command, and the next identical
      command runs with no second question.
- [ ] A `decline` does not run the command, and the result says the person
      refused. It is not a cancelled run.
- [ ] An `ask` decision with no bound `ToolContext` refuses, as it does today.

## Tests

- [ ] New `Tests/FoundationModelsMultitoolTests/ShellAskElicitationTests.swift`.
- [ ] A fake sink and a fake mailbox answer the elicitation. Assert that the
      request is form mode, and that it carries the four choices.
- [ ] A test for each of the three actions: `accept`, `decline`, and `cancel`.
- [ ] A test proves the "always allow" answer reaches `ShellDecisionStore`, and
      that a second identical command sends no second request.
- [ ] A test with `ToolContext.current` unbound asserts the refusal.
- [ ] `swift test --filter ShellAskElicitation` passes.
- [ ] `swift test` passes with no new failure and no new warning.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #phase-2 #eventplan