---
comments:
- actor: claude-code
  id: 01m1yf4af6cnppkyckax09vmh4
  text: |-
    Research done. The blocker is lifted.

    - Upstream FoundationModelsRouter `main` is now `efe0147`, and it deletes `LanguageModelProfile.release()`. The repo was pinned at `ba55154`, which still had it.
    - `Package.resolved` is untracked (gitignored, commit `cf9cb2d`), so "this repo picking up that router revision" is a local `swift package update FoundationModelsRouter`. Done for the root package and for `IntegrationTests`.
    - `swift build` after the update fails at exactly the two call sites the card names: `Sources/MultitoolCLI/CLIRunner.swift:948` and `:950`, "value of type 'LanguageModelProfile' has no member 'release'". Nothing else in the root package broke.

    How residency works now (read from the router at `efe0147`):

    - `ResidencyHold` is a `package final class`. Its `deinit` calls `Router.enqueuePendingRelease(token)`, which appends to a `Mutex`-guarded queue synchronously on the releasing thread and also starts an eager drain `Task`. The queue, not the task, is what makes the release certain.
    - `Router.resolve` -> `runResolvePipeline` calls `drainPendingReleases()` under `poolLock` immediately before `hostBudget()`. Any hold whose `deinit` finished before that point is freed before the budget is measured.
    - `RoutedLLM`/`RoutedEmbedder` each hold the `ResidencyHold` strongly, so a tool that keeps only `profile.flash` keeps the model resident. A live session retains the profile through `owningProfileSlot`.

    Third subtask, the one that needed thought: no scenario holds a handle or a session past `tearDown()`.

    - `withLiveRouterFixture` (ScenarioRunner) makes the fixture a local, calls `body(fixture)`, then `tearDown()`. Every session and every tool the body builds is a local of the closure and is gone before `tearDown()` runs.
    - `SelectionForkPerCallTests` builds `SearchToolsTool(registry:librarian: fixture.profile.flash)` as a local in the same `do` block as `tearDown()`; it is released when that block ends, before the test function returns.
    - `ShellBackgroundRunner`'s `watcher` `Task` is awaited inside the body and its result holds no model handle. `session.close()` runs inside the body.
    - No suite property, global, or long-lived task stores a profile, a handle, or a fixture.
    - The suite runs `--no-parallel` (`IntegrationTests/Package.swift`), so each test function returns, releasing every local, before the next test resolves.

    Discovered, out of this card's scope: `plan.md:340-341` and `plan.md:347` still describe `release()` as the way to evict a profile. A separate card follows.
  timestamp: 2026-09-07T17:37:20.358717+00:00
- actor: claude-code
  id: 01m1yn1ta6my085cnj8j4qdfaa
  text: |-
    Implementation landed, and the runs are green.

    Changes:
    - `Sources/MultitoolCLI/CLIRunner.swift` — both `await profile.release()` calls and the eight-line cleanup comment above the `do` are gone. The `catch` only rethrows, as the acceptance criteria state.
    - `IntegrationTests/.../Support/LiveRouterFixture.swift` — `profile.release()` is gone from `tearDown()`; `liveProfileTurnstile.release()` stands. The `tearDown()` doc comment now says the models are not evicted here, why (ARC owns residency, the next `resolve` drains before it measures the budget), and what a scenario must therefore not do. The `profile` property comment, which also said "release via `tearDown()`", is corrected for the same cause.

    Runs:
    - `swift build` — Build complete, no new warning. The one warning printed, "missing creator for mutated node: (... mlx-swift_Cmlx.bundle/Contents/MacOS)", is a SwiftPM build-graph warning that stands before this change and names no file of this repo.
    - `swift build --package-path IntegrationTests --build-tests` — Build complete.
    - `swift test` — "Test run with 1401 tests in 109 suites passed", three consecutive runs.
    - `swift test --package-path IntegrationTests --no-parallel` — "Test run with 21 tests in 14 suites passed after 1546.917 seconds", 0 skipped. The log holds 12 `RESOLVED` lines in that one process, so twelve live profiles were resolved back to back with nothing calling `release()`. That is the proof the card asked for: each fixture's models were really freed before the next resolve measured the budget.
    - `grep -rn 'profile.release()' --include='*.swift' .` returns nothing.
    - The turnstile is still given back on every exit path: `LiveRouterFixture` acquires at one place and releases in the resolve-failure `catch` and in `tearDown()`; `CLISmokeTests` acquires and releases its own.

    What did not work the first time, so the next agent does not chase it: the first full integration run failed 3 of 21 with "Time limit was exceeded" — `AsyncFanOutTests` (600s), `BackgroundTests` (600s) and `NestedGenerationProbeTests` (60s). Those were the first two tests of the run plus one soon after, on a cold page cache, and the profile is 38.8GB of weights coming off disk. A re-run of exactly those three suites passed in 159 seconds total (62s, 43s, 10s), and the warm full run passed all 21. The failures were load time, not residency: a leak would have starved the LATER scenarios, and every later scenario passed in both runs.

    Also recorded: `swift test` printed "1 issue" on one cold run whose full log was lost to a `tail` in the command. Three later full runs were clean, 1401/1401 each.
  timestamp: 2026-09-07T19:20:49.734677+00:00
- actor: claude-code
  id: 01m1yn2p4yz93bd6apkh5ea666
  text: |-
    ### implement — changed
    - evidence: 2 files — Sources/MultitoolCLI/CLIRunner.swift, IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Support/LiveRouterFixture.swift. `swift build` complete with no new warning; `swift test` 1401 tests in 109 suites passed; `swift test --package-path IntegrationTests --no-parallel` 21 tests in 14 suites passed in 1546.9s, 0 skipped, 12 live resolves in the one process.
    - next: /review
  timestamp: 2026-09-07T19:21:18.238746+00:00
position_column: doing
position_ordinal: '80'
title: Drop the profile.release() calls once router residency is ARC-owned
---
## What

FoundationModelsRouter is making pooled residency ARC-owned. A resident model is freed when the last reference to it goes away, and `Router.resolve` drains the pending evictions before it measures the host budget. `LanguageModelProfile.release()` is then deleted (router tasks `^fa7b61c`, `^5ph8cdm`, `^m8vj0jr`).

This repo calls it in two places, and both can simply go away.

- `Sources/MultitoolCLI/CLIRunner.swift:948` and `:950` — the demo releases the profile on the success path and again in the `catch` before it rethrows. The comment at `:839-846` explains the whole construction: `release()` is async, so it cannot run in a synchronous `defer`, and an unstructured cleanup `Task` would never finish before `main.swift` calls `exit(_:)`. Delete both calls and that comment. After the router change the profile is freed when `run(...)` returns and the last reference goes away, so the `do`/`catch` exists only for the rethrow.
- `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Support/LiveRouterFixture.swift:580` — `tearDown()` releases the profile, then gives back `liveProfileTurnstile`. Delete only the `profile.release()` line. **Keep `liveProfileTurnstile.release()` at `:581`** — that is the fixture's own semaphore, not the router API, and the one-live-profile-at-a-time serialization still depends on it. Update the doc comment at `:575-578`, which says the call evicts the three resident models.

The fixture is the case that needs thought. `tearDown()` is what makes the next scenario's resolve fit. After the change, the eviction happens when the fixture and every handle taken from it are unreferenced, and the next `resolve` drains before it measures. Confirm the fixture holds no handle past `tearDown()` — if a scenario stored `profile.flash` or a session somewhere that lives longer than the fixture, the models stay resident and the next scenario fails its budget. That is the real work here; the two deletions are trivial.

Nothing else in this repo is affected. Tools built over a `RoutedLLM` keep their models resident by themselves after the change, so the registry's librarian handle (`profile.flash`, passed to `makeSessionToolsAndStaging(librarian:)` at `CLIRunner.swift:868`) needs no change.

- [x] Delete both `profile.release()` calls and the `:839-846` comment in `Sources/MultitoolCLI/CLIRunner.swift`.
- [x] Delete `profile.release()` in `LiveRouterFixture.tearDown()` and correct its doc comment; keep the turnstile release.
- [x] Confirm no scenario holds a handle or session past `tearDown()`, so the next scenario's resolve still fits.

## Blocked on

Router `^m8vj0jr` (the deletion of `release()`), and this repo picking up that router revision in `Package.resolved`. Until then the calls still compile.

**Cleared.** Router `main` is `efe0147`, which deletes `release()`. `Package.resolved` is untracked, so the pickup is a local `swift package update FoundationModelsRouter`, done for the root package and for `IntegrationTests`.

## Acceptance Criteria

- [x] `grep -rn 'profile.release()' --include='*.swift' .` returns nothing.
- [x] `liveProfileTurnstile.release()` is still called on every exit path in `LiveRouterFixture`.
- [x] The `CLIRunner` demo path has no cleanup call and no cleanup comment; the `catch` only rethrows.
- [x] `swift build` reports no new warnings.

## Tests

- [x] Run `swift test`. Every hermetic suite passes.
- [x] Run `swift test --package-path IntegrationTests`. Every scenario passes, and in particular two scenarios in a row both resolve — that proves the first fixture's models were really freed before the second resolve measured the budget.
- [x] Confirm the runs reported the tests as executed. A `--filter` that matches a display name instead of a type name matches nothing and still exits `0`.

## Workflow

- Use `/tdd`. Start from the integration run, because the fixture teardown is what the change actually tests. #router #tech-debt