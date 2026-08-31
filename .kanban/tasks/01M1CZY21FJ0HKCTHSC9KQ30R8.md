---
assignees:
- claude-code
position_column: todo
position_ordinal: '8180'
title: Split ScenarioRunner so the 50 model-free integration tests join the fast suite
---
## What

50 of the 71 tests in the nested `IntegrationTests` package need no model at
all. They test the scenario harness itself, and they run only when a person
runs the gated suite:

| suite | tests | live-model references |
| --- | --- | --- |
| `ScenarioFailureModeTests` | 22 | 0 |
| `ScenarioFixtureTests` | 20 | 0 |
| `ScenarioGradingTests` | 8 | 0 |

None of the three names `LanguageModelSession`, `SystemLanguageModel`,
`LiveRouterFixture` or `runNativeIntegrationScenario`.

## Why they cannot move today, which is also the simplicity problem

`Tests/.../Support/ScenarioRunner.swift` is **1704 lines** and holds two
unrelated things: the grading and evidence logic, which is pure, and the
live-model driving, which needs a `LiveModelLoader`, the Metal bootstrap and
the turnstile. The 50 tests depend on the first and would drag in the second.

The split is the file's natural shape already. Its neighbours are each one
thing:

- `Support/ScenarioFailureModes.swift` — 253 lines, no live reference
- `Support/LiveRouterFixture.swift` — 663 lines, live only

`ScenarioRunner.swift` is the only file that straddles.

## What to do

1. Split `ScenarioRunner.swift` along the seam it already has: the pure
   grading and evidence types on one side, the live-fixture driving on the
   other.
2. Give the pure side a home both packages can link. The root package already
   has this pattern — `Tests/Support/MCPTestServer` and
   `Tests/Support/TestConcurrency` are test-support products of the root
   manifest, declared at `Package.swift` around lines 456 and 463.
3. Move `ScenarioFailureModeTests`, `ScenarioFixtureTests` and
   `ScenarioGradingTests` into the root test target.

## What this is worth

- Those 50 tests join the root suite, which is **1316 tests in 6.5 seconds**,
  so they run on every commit instead of only when a person opts in.
- The gated package becomes only what a gated package is for: real inference.
  21 tests, all of which genuinely drive a model.
- The largest file in the suite stops doing two jobs.

## What must NOT change with it

Two costs in the gated suite are deliberate, are documented with a
measurement, and protect the reliability signal the suite exists to give.
Neither is in scope here and neither should be "tidied" while nearby:

1. **A fixture resolves per scenario and releases at teardown.** Sharing one
   would be faster and would let a prompt cache carry between scenarios. The
   measured failure was a model that narrated a tool call it never made,
   because its context already held one.
2. **`--no-parallel`.** Measured at 661 seconds parallel against 852 serial,
   thus it costs about 190 seconds and buys correct attribution.

## Acceptance Criteria

- [ ] `ScenarioRunner.swift` no longer holds both the pure grading logic and
      the live-model driving.
- [ ] `ScenarioFailureModeTests`, `ScenarioFixtureTests` and
      `ScenarioGradingTests` run in the root test target.
- [ ] The nested package holds only tests that drive a model.
- [ ] Neither the per-scenario fixture nor `--no-parallel` is changed.

## Tests

- [ ] `swift test` at the root passes, with 1366 tests or more — the current
      1316 plus the 50 that moved — and the run time recorded on this card.
- [ ] `swift test --package-path IntegrationTests --no-parallel` passes with
      the remaining tests, and its time recorded.
- [ ] No assertion changes. This moves tests and splits a file; a test whose
      meaning changes is out of scope.

## Found by

Task `^jmtpfwv`, which ran the gated suite on 2026-08-31 and counted which of
its tests need a model. #eventplan</description>
