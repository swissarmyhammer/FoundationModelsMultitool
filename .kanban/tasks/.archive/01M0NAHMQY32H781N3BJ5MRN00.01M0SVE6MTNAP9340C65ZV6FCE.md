---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0ny4r0t1g1gzvdw699k1z31
  text: |
    ### finish iteration 1 — no-change (the board was wrong, not the card)
    - implement: no-change — no file was touched. The implementer read the source and found that this card cannot compile on its own.
    - cause: `ShellPolicy` holds a `let decisions: ShellDecisionStore`, its initializer takes one, `remember(_:for:in:)` writes through it, and two `ShellPolicyError` cases carry a `ShellDecisionStore.Scope`. The store must land first. The plan of 2026-08-22 wrote the dependency backwards.
    - correction: the dependency edges are reversed.
      - `^desmgsm` (Port ShellDecisionStore) now depends on `^pfa3der` only.
      - This card now depends on `^desmgsm`.
      - `^dkhwgwr` (route ask through elicit) now depends on this card.
    - next: `^desmgsm` runs first. Then this card.
  timestamp: 2026-08-22T23:50:51.162998+00:00
- actor: claude-code
  id: 01m0svdaj5gct0hpkz9g8scvrm
  text: |-
    ### Cancelled by decision 2026-08-24 — the shell has no policy layer

    The seatbelt sandbox is the only gate. There is no allow, no deny, and no ask.

    The reason: a denylist over command text is bypassable, and the `matchKey`
    header of the deleted decision store already argued this at length — quoting
    starts again inside `$( )`, and a lexer that is a little wrong grants what
    nobody granted. The sandbox is a kernel boundary and does not care how a command
    is spelled.

    Two consequences are carried by new cards, because this card owned them:
    - The command-length and environment-value-length caps move to `ShellRunner`
      (`^xgnygf8`). `ShellRunner.swift:289` deferred them here, thus they would
      otherwise be unowned.
    - `SeatbeltSandbox` docs stop deferring to this type (`^98zgzyq`).
  timestamp: 2026-08-24T12:20:04.293171+00:00
depends_on: []
position_column: doing
position_ordinal: '80'
title: Port ShellPolicy, the allow, deny, and ask decision
---
## What

Port the security policy that vets a command, its environment, and its working
directory before the command runs. Port it without a behavior change. The `ask`
outcome keeps its refusal behavior in this task. A later task routes `ask`
through elicitation.

- Create `Sources/FoundationModelsMultitool/Capabilities/Shell/ShellPolicy.swift`
  from `../FoundationModelsShelltool/Sources/ShellTool/ShellPolicy.swift`
  (941 lines).
- Keep the three outcomes: allow, deny, and ask.
- Keep the stacked overlays: builtin, user, and project.
- The file imports `Yams`. It must not import `Operations`.

## Acceptance Criteria

- [ ] `ShellPolicy` is in
      `Sources/FoundationModelsMultitool/Capabilities/Shell/`.
- [ ] The three outcomes and the overlay stack behave as they do in Shelltool
      today.
- [ ] A command that the builtin overlay denies is denied.
- [ ] A project overlay overrides a user overlay, and a user overlay overrides
      the builtin overlay.
- [ ] The file does not import `Operations`.

## Tests

- [ ] New `Tests/FoundationModelsMultitoolTests/ShellPolicyTests.swift`,
      ported from
      `../FoundationModelsShelltool/Tests/ShellToolTests/ShellPolicyTests.swift`.
- [ ] New `Tests/FoundationModelsMultitoolTests/ShellPolicyDecisionTests.swift`,
      ported from the file of the same name in Shelltool.
- [ ] New `Tests/FoundationModelsMultitoolTests/ShellPolicyValuesTests.swift`,
      ported from the file of the same name in Shelltool.
- [ ] `swift test --filter ShellPolicy` passes.
- [ ] `swift test` passes with no new failure and no new warning.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #phase-2 #eventplan