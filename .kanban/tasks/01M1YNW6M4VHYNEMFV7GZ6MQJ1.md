---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m1yp860z96sbhf01sew6pwaq
  text: |-
    Picked up. Research notes:

    - `IntegrationTests/Package.swift` holds the two stale claims the card names: the `--no-parallel` reason in the package doc comment ("queues behind `liveProfileTurnstile` for the one resident live profile"), and the `TestConcurrency` dependency comment ("it holds this target to one resident live profile").
    - `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Support/LiveRouterFixture.swift` is already correct: its `liveProfileTurnstile` doc says "this turnstile already admits one live profile at a time", which attributes the limit to the gate, not to the Router; and `LiveRouterFixture.profile` already says "Router owns its residency by ARC".
    - The `release()` calls in `LiveRouterFixture.swift` are `ConcurrencyGate.release()`, which gives the turnstile back. They are not profile residency calls, so they stay.
    - Plan: keep the `--no-parallel` requirement and the time-limit measurement; replace only the cause, so the turnstile admits one live scenario at a time because concurrent generation destroys grounding.
  timestamp: 2026-09-07T19:41:46.911373+00:00
- actor: claude-code
  id: 01m1ypbgvhkd27v4z59t92h8gz
  text: |-
    Repository-wide sweep for the stale residency wording, `.build` and `.kanban` excluded.

    `release()` against a profile: none. Every `release()` in the repository belongs to a `ConcurrencyGate`, a `ReleaseGate`, a latch or a `liveContexts` counter. No call evicts a profile.

    "one resident" / "resident at a time" — three sites keep a claim this card does not cover, so they are recorded on new card `^phe0b2q`:

    - `IntegrationTests/Tests/.../SearchThenCallTests.swift` — the `.serialized` reason says "only one profile is resident at a time per `Router`".
    - `IntegrationTests/Tests/.../Support/LiveRouterFixture.swift` — the `liveProfileTurnstile` doc quotes that same sentence.
    - `Tests/Support/TestConcurrency/ConcurrencyGate.swift` header — "the integration target holds its scenarios to one resident live model profile"; it names the gate as the actor, so it may already be correct.

    Four other matches are true under pooled residency and must stay: `Sources/MultitoolCLI/CLIRunner.swift` and `LiveRouterFixture.swift` say that sharing one `ModelRef` across both slots gives one resident container, which is what a reference-counted pool does.

    `LiveRouterFixture.swift` needs no correction for the Router itself: it already says "Router owns its residency by ARC" and "The three resident models are not evicted here".
  timestamp: 2026-09-07T19:43:36.305310+00:00
- actor: claude-code
  id: 01m1ypjwrk380crqtzw2cmfert
  text: |-
    ### implement — changed
    - evidence: 1 file — IntegrationTests/Package.swift. Two comments corrected. The `--no-parallel` paragraph now gives the cause as the turnstile, which admits one live scenario at a time because concurrent generation destroys grounding; the `--no-parallel` requirement, the time-limit reasoning and the pointer to `LiveRouterFixture.swift` all stay. The `TestConcurrency` dependency comment now says the turnstile holds this target to one live scenario at a time.
    - builds: `swift build --package-path IntegrationTests` exit 0; `swift build --package-path IntegrationTests --build-tests` exit 0 (the step CI runs on every run); `swift build` at the root exit 0. LSP diagnostics on the working set: 0 errors, 0 warnings. The one build line that says `warning: missing creator for mutated node` names the `mlx-swift_Cmlx.bundle` build graph, is on the root build too, and no comment can reach it.
    - rules: the full validator dump for `.swift` was read end to end. No rule is touched. Two completeness validators state that a comment or doc edit is not a finding. `no-commented-code` cannot fire because the new text reads as English prose. This manifest carries no `swiftlint:disable` or `periphery:ignore` directive, so the placement hazard (a doc line between a directive and its declaration) does not exist here.
    - next: `/review`. Follow-up card `^phe0b2q` holds the three remaining sites outside this card's scope.
  timestamp: 2026-09-07T19:47:37.875869+00:00
- actor: claude-code
  id: 01m1ypq5g1ym3cbwv3gem2jt86
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (6530660) — zero new findings; 7 validator runs, 0 failed, 0 skipped; no prior findings section
    - next: task moved to done
  timestamp: 2026-09-07T19:49:57.889978+00:00
- actor: claude-code
  id: 01m1ypqfm2d8aky6q9vvxgfzyv
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 1 file (IntegrationTests/Package.swift); both doc comments now give the true cause of --no-parallel
    - test: green — swift build, swift build --package-path IntegrationTests, and --build-tests all exit 0; LSP 0 errors 0 warnings. The 25-minute integration suite was not run, because the change is a comment.
    - commit: 6530660
    - review: clean — zero new findings; task moved to done
  timestamp: 2026-09-07T19:50:08.258392+00:00
position_column: done
position_ordinal: ffb680
title: IntegrationTests/Package.swift doc comment still claims one resident live profile
---
## What

Card `^s8e14a7` corrected the three remaining single-residency claims in `plan.md`. The same stale claim stays in a Swift doc comment.

`IntegrationTests/Package.swift`, in the comment that gives the reason for `--no-parallel`:

> every scenario here queues behind `liveProfileTurnstile` for the one resident live profile

Router residency is pooled and reference-counted, so more than one profile can be resident. The `--no-parallel` requirement itself stands: the turnstile admits one live scenario at a time because concurrent generation destroys grounding, and Swift Testing spends a test `.timeLimit` on queue time. Correct the cause; keep the requirement.

The same file, near the target dependency on `TestConcurrency`, says the gate "holds this target to one resident live profile". Check that line too.

## Acceptance Criteria

- [ ] `IntegrationTests/Package.swift` makes no claim that the Router keeps one profile resident at a time.
- [ ] The `--no-parallel` reason it gives is true for pooled residency.
- [ ] The `--no-parallel` requirement stays.

## Tests

- [ ] None. The change is a comment. `swift build` must stay clean. #router #tech-debt #docs