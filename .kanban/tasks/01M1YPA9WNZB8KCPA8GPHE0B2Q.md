---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m1ypw86271t482xkkv3mnff8
  text: |-
    Research and decision on the three named sites.

    Precedent read from commit `6530660` (`IntegrationTests/Package.swift`, card `^gz6mqj1`): the settled wording is "one live scenario at a time", with the grounding measurement as the cause and the turnstile named as a rule of the target.

    1. `SearchThenCallTests.swift` suite doc — corrected. `.serialized` no longer mirrors "only one profile is resident at a time per `Router`". It now says `.serialized` holds the four scenarios to one at a time inside the suite, which is what `liveProfileTurnstile` holds across suite boundaries, because concurrent live scenarios come back fluent but ungrounded. It states plainly that this is a rule of the target and not a limit of `Router`, whose residency is pooled and reference-counted. The `.serialized` trait, the `.timeLimit`, the `--no-parallel` command line and the heavy-weight-loading reason all stay.

    2. `LiveRouterFixture.swift`, the `liveProfileTurnstile` doc — corrected. The quoted sentence is gone. The paragraph keeps the five-at-once grounding measurement, keeps "a correctness requirement of this target, not a courtesy", and now says the requirement is a rule of the target rather than a limit of `Router`. The `--no-parallel` section below it, its stated cause (what the clock counts) and the 2026-08-16 measurement table are untouched.

    3. `Tests/Support/TestConcurrency/ConcurrencyGate.swift` header — left as written. Decision: the sentence is "the integration target holds its scenarios to one resident live model profile." The actor is the integration target, not `Router`, so it makes no claim about Router residency; the card says to correct it only if it reads as a claim about Router.

    The same judgment covers `LiveRouterFixture.resolve()`'s own doc line ("at most one integration scenario in the target has a profile resident at a time"), which names the turnstile as the actor as well and is therefore left as written. These two are the only lines a whole-repository grep still returns for the residency phrasings, and neither names `Router`.

    The four `ModelRef` sentences in `CLIRunner.swift` and `LiveRouterFixture.swift` were left alone, as the card directs.
  timestamp: 2026-09-07T19:52:44.482594+00:00
- actor: claude-code
  id: 01m1ypwekxc69z27khapgw6x09
  text: |-
    ### implement — changed
    - evidence: 2 files — IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/SearchThenCallTests.swift, IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Support/LiveRouterFixture.swift. Tests/Support/TestConcurrency/ConcurrencyGate.swift judged correct as written and left unchanged.
    - runs: `swift build` clean; `swift build --package-path IntegrationTests --build-tests` clean; `swift test` green — 1401 tests in 109 suites, 0 failures. The 25-minute integration suite was not run: the change is a comment.
    - grep: whole repository, excluding `.build` and `.kanban` — no file claims `Router` keeps one profile resident at a time. Two lines still carry the word "resident" and both name the test target's own turnstile as the actor, never Router.
    - follow-up: none filed. The chain closes here.
    - next: /review
  timestamp: 2026-09-07T19:52:51.069188+00:00
position_column: doing
position_ordinal: '80'
title: SearchThenCallTests and LiveRouterFixture still quote "only one profile is resident at a time per Router"
---
## What

Found while working `^gz6mqj1`, which corrected the same stale claim in `IntegrationTests/Package.swift`. Router residency is pooled and reference-counted, so more than one profile can be resident. Two files still say it is one.

`IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/SearchThenCallTests.swift`, in the suite doc comment that gives the reason for `.serialized`:

> `.serialized` mirrors Router's own gated suite: only one profile is resident at a time per `Router`

`IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Support/LiveRouterFixture.swift`, in the `liveProfileTurnstile` doc comment, which quotes that same sentence:

> it is the same property `SearchThenCallTests`' own `.serialized` documents ("only one profile is resident at a time per `Router`"), extended across suite boundaries where a suite trait cannot reach.

The true reason is above it in the same comment, and it is a measurement: concurrent live scenarios come back fluent but ungrounded. The gate, not the Router, holds the target to one live scenario at a time.

Also read `Tests/Support/TestConcurrency/ConcurrencyGate.swift`, the file header:

> the integration target holds its scenarios to one resident live model profile.

That one names the gate as the actor, so it may be correct as written. Decide, and correct it only if it reads as a claim about Router.

Leave alone the four places that say sharing one `ModelRef` gives one resident model or container (`CLIRunner.swift`, `LiveRouterFixture.swift`). Those are true under pooled residency: the same `ModelRef` resolves to the same pooled container.

## Acceptance Criteria

- [ ] No file claims the Router keeps one profile resident at a time.
- [ ] The `.serialized` trait on `SearchThenCallTests` stays, with a reason that is true for pooled residency.
- [ ] The turnstile doc keeps its grounding measurement and its `--no-parallel` requirement.

## Tests

- [ ] None. The change is a comment. `swift build` and `swift build --package-path IntegrationTests` must stay clean. #docs #router #tech-debt