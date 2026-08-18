---
assignees:
- claude-code
position_column: todo
position_ordinal: '8780'
title: Registry.affordances omits `wait`, which is mounted in both modes
---
`Registry.affordances` (`Sources/FoundationModelsMultitool/MultiTool.swift:91`) reports `["runCode"]` in direct mode and `["runCode", "searchTools"]` otherwise. `makeSessionTools(librarian:)` in the same type mounts `WaitTool()` on both paths — `[MultiTool(registry: self), WaitTool()]` at `:171` and `[searchTools, runCode, WaitTool()]` at `:188`, with the comment at `:167` stating the intent outright: "`wait` is mounted in both modes".

So a public property documented as "the session-facing operations this registry surfaces" leaves out one of the operations it surfaces, in every mode.

This is the same class as `^hgxcy0y` — text that says direct mode drops `wait` — one layer down, and it was not caught by that card because `^hgxcy0y` covered comments and `--help` text alone. This one is a value a caller reads.

## Why it is not a one-line fix

`affordances` is `public`, and the doc at `:142` draws a real distinction: it "names which operations a registry surfaces, for a caller or a test to check; it is a capability list, not a mount order". Adding `wait` is consistent with that reading. But two unit tests pin the current value:

    Tests/FoundationModelsMultitoolTests/MultiToolExecutionTests.swift:303
        #expect(registry.affordances == ["runCode", "searchTools"])
    Tests/FoundationModelsMultitoolTests/MultiToolExecutionTests.swift:309
        #expect(direct.affordances == ["runCode"])

so the change moves a public value and its tests together.

## What to decide

- Add `wait` to both arms, and say in the doc where in the list it belongs (the property is not a mount order, so the position is a readability choice, not a contract).
- Or keep the list as it is and correct the doc to say what it really enumerates — the operations a *snippet author* chooses between, with `wait` excluded because a snippet never calls it. If this is the answer, say so at the declaration, because the current wording does not support it.

Do not change the value and the doc in opposite directions.

## Acceptance Criteria

- [ ] `affordances`'s value and its doc comment agree with `makeSessionTools(librarian:)`
- [ ] `MultiToolExecutionTests`' two assertions state the chosen contract
- [ ] Ungated `swift test` green
