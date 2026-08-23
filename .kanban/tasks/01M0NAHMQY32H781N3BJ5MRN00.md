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
depends_on:
- 01M0NAJ1KNMZS1NVDA6DESMGSM
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