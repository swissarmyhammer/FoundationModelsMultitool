---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0b8va0wy3jbznrtr0f3wybv
  text: |-
    ## Done — `wait` added to both arms, and the class closed rather than the instance

    **The decision.** Added `wait`, not narrowed the doc. `wait` is a mounted tool the model calls exactly as it calls `runCode` and `searchTools`, `makeSessionTools(librarian:)` mounts it on both paths with a comment saying so, and `README.md` already states the contract that way — direct mode takes discovery away, never detachment. Reading `affordances` as "operations a *snippet author* chooses between" would have needed the doc rewritten against three other places that already agree with each other.

        affordances   ["runCode", "searchTools"]  ->  ["runCode", "searchTools", "wait"]
        (direct)      ["runCode"]                 ->  ["runCode", "wait"]

    The order stays as it was, with `wait` appended; the declaration says explicitly that this property is not a mount order and points at `makeSessionTools(librarian:)`, which owns one.

    **The class, not just the site.** Auditing every place that describes what direct mode vends turned up four more instances of the same forgetting, all fixed in the one commit:

    - `MultiTool.swift` — `directMode()`'s own doc said "only `runCode` is surfaced to the session".
    - `MultiToolExecutionTests` — the MARK read "directMode(): a runCode-only surface".
    - `MultiToolExecutionTests` — a test named "…a plain registry reports both", now three.
    - `MultiToolExecutionTests` — a test named "vends runCode alone" whose own assertion one line below already read `["runCode", "wait"]`.
    - `plan.md:91` — the schema-bloat argument said the main session carries "only `runCode` + `searchTools`", which is three schemas, not two. This one is in a design section, so the banner's rule says correct it rather than keep it.

    **Tests.** Both `MultiToolExecutionTests` assertions state the chosen contract, with a comment giving the reason at the assertion. Ungated `swift test` green: 359 tests / 30 suites, and 59 / 11. `review sha HEAD~1..HEAD` — 0 findings.

    No gated run: this is a pure metadata property with no live-inference path, and `makeSessionTools(librarian:)` — the thing the gated suites actually drive — is unchanged.
  timestamp: 2026-08-18T20:26:17.500613+00:00
position_column: done
position_ordinal: d180
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
