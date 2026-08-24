---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0rhfg7qxtxdrfr9q1tfaemc
  text: |-
    Picked up. Research notes.

    - `MultiTool.Builder` keeps one `pending` list of `.standalone` / `.grouped` items. `withCapability(_:)`, `addGroup(named:_:)` and `register(noun:tool:)` all queue `.grouped`, so today nothing tells a capability registration from a group registration.
    - `buildRegistry()` validates in one loop (illegal noun, duplicate name in one group, duplicate standalone name) and one post-loop check (standalone name against group name). The post-loop check is the prevailing place for an order-independent rule.
    - `MultiToolBuilderError.Kind` has two cases today. No `switch` over `Kind` exists anywhere in the tree — every use is `==` in a test — so a new case breaks no caller.
    - An existing test, `duplicateNounAndVerbThrows`, registers ONE capability two times and expects `.duplicateName` with name `first`. To keep that test green, the new ownership check must run AFTER the render loop, so a real path collision is still reported as a path collision.
    - No test today proves that two `addGroup(named:)` calls with one group name merge. The card asks for one; it goes in `BuilderSurfaceTests.swift`, beside the other `addGroup` tests.
    - A capability has only a noun and its tools, so the only identity a message can name is the capability TYPE. To prove the message names BOTH claimants, the test target needs a second `Capability` fixture type whose name is not a substring of `FixtureCapability`.
  timestamp: 2026-08-24T00:07:15.447882+00:00
- actor: claude-code
  id: 01m0rhs9xq86apdtv407an9vnw
  text: |-
    Implementation landed, by /tdd.

    RED first: the four new tests named `.duplicateNoun`, which did not exist, so the test target did not compile. GREEN after the case and the ownership check landed.

    What the code does now.

    - `MultiToolBuilderError.Kind` gains `duplicateNoun`. Its doc states why it is not `duplicateName`: that case reports two tools at one path, this one reports ownership and holds even where every path differs.
    - `Builder` keeps `capabilityClaims`, one `CapabilityClaim` for each `withCapability(_:)` call. A claim holds the noun, the claimant type name, and the half-open range of `pending` positions the capability's own tools fill. The range is what tells a capability's own entry from an entry another registration put under the same noun, because all three registrations queue the same `.grouped` item.
    - `withCapability(_:)` records the claim and then calls `register(noun:tool:)` for each tool, as before.
    - `buildRegistry()` calls `validateNounOwnership(standaloneNames:)` AFTER the render loop and BEFORE the standalone-against-group check. That order is deliberate: a real path collision keeps its `.duplicateName` report, so the existing test `duplicateNounAndVerbThrows` is untouched and still green.
    - Three failures raise `.duplicateNoun`, and each message names the noun and both sources: two capabilities that claim one noun (both type names), a group or `register` call under a claimed noun (the capability and the tool), and a standalone tool that wears a claimed noun.

    Discoveries worth keeping.

    - A capability holds a noun and its tools and nothing else, so its TYPE name is the only identity a message can give it. The test target needed a second fixture capability type, `SecondCapability`, to tell one claimant from the other; its name is no substring of `FixtureCapability`, so each `contains` test reads exactly one claimant.
    - `tool.name` reads correctly off `any Tool`, so the group-collision message can name the offending tool.
    - No `switch` over `Kind` exists in the tree, so the new case broke no caller.

    Tests: `swift test` — 595 tests in 46 suites, 0 failures. `swift build --build-tests` after touching every changed file: no compiler warning. The one line on stderr is the pre-existing SwiftPM message about the `mlx-swift_Cmlx.bundle` node.
  timestamp: 2026-08-24T00:12:36.663874+00:00
- actor: claude-code
  id: 01m0rhsj6exdas8w8fc41wje2r
  text: |-
    ### implement — changed
    - evidence: 5 files — Sources/FoundationModelsMultitool/Surface/MultiToolBuilder.swift, Sources/FoundationModelsMultitool/Surface/Capability.swift, Tests/FoundationModelsMultitoolTests/CapabilityRegistrationTests.swift, Tests/FoundationModelsMultitoolTests/BuilderSurfaceTests.swift, Tests/FoundationModelsMultitoolTests/Fixtures/CapabilityRegistrationFixtures.swift. `swift test`: 595 tests in 46 suites, 0 failures, 0 compiler warnings. Every acceptance criterion and every listed test of the card is in the diff.
    - next: /review
  timestamp: 2026-08-24T00:12:45.134996+00:00
- actor: claude-code
  id: 01m0rj4tc1kz2d4wbs2akpkp63
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit 2b1880e) — 0 findings, 0 confirmed, 0 refuted, 7 attempted, 0 failed. 5 files reviewed; 4 `.kanban/` files excluded by `.reviewignore`.
    - next: task moved to `done`. No prior `## Review Findings` section to carry.
  timestamp: 2026-08-24T00:18:53.953012+00:00
- actor: claude-code
  id: 01m0rj5hnchvm2w2h1r2h1v795
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 5 files (Surface/MultiToolBuilder.swift, Surface/Capability.swift, Tests/CapabilityRegistrationTests.swift, Tests/BuilderSurfaceTests.swift, Tests/Fixtures/CapabilityRegistrationFixtures.swift)
    - test: green — swift test, 595 passed in 46 suites, 0 failed, 0 skipped
    - commit: 2b1880e feat(surface): make withCapability(_:) claim ownership of its noun
    - review: clean — zero findings; the task is in done
  timestamp: 2026-08-24T00:19:17.804030+00:00
position_column: done
position_ordinal: e780
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