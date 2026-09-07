---
assignees:
- claude-code
position_column: todo
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