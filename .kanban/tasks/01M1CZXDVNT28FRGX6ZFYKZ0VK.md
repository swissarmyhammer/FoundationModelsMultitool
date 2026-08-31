---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m1d0tw2xav760j7j46n5vnyk
  text: |-
    ### implement — changed

    Done, and verified by a full run. Commit `35b056f`.

    `swift test --package-path IntegrationTests --no-parallel`: **71 tests in 17 suites, all passed, 847.6 seconds.**

    Measured against the new ceilings:

    | suite | measured | ceiling | headroom |
    | --- | --- | --- | --- |
    | In-band collection canary | 197.7 s | 15 min | 4.5x |
    | Search-then-call | 194.8 s | 12 min | 3.7x |
    | Respond self-drain | 130.0 s | 10 min | 4.6x |
    | CLI smoke | 125.6 s | 10 min | 4.8x |
    | Shell on the background path | 60.9 s | 15 min | 15x (left alone) |
    | Async fan-out | 53.3 s | 10 min | 11x |

    **The variance between the two runs is the useful result, and it argues for the headroom rather than against it.** The same suites on the same machine, one run apart:

    - Respond self-drain: 95.1 s then 130.0 s, plus 37 percent
    - CLI smoke: 106.0 s then 125.6 s, plus 18 percent
    - In-band canary: 254.9 s then 197.7 s, minus 22 percent
    - Whole package: 824.9 s then 847.6 s

    Real inference does not take the same time twice. A ceiling set at 1.5 times one measurement would have put Respond self-drain within reach of its limit on the second run. Three times measured absorbs this; anything tighter should not be attempted without measuring several runs on the CI runner itself, which is a different and slower machine.

    next: nothing. All three criteria are met.
  timestamp: 2026-08-31T23:00:25.309714+00:00
position_column: done
position_ordinal: ffa780
title: Bring the integration suite time limits down to what the suite measures
---
## What

Every suite of the nested `IntegrationTests` package declares a time limit
between 9 and 38 times what the suite actually takes. Measured on 2026-08-31,
one full run of `swift test --package-path IntegrationTests --no-parallel`,
71 tests in 17 suites, 824.9 seconds:

| suite | measured | declared | ratio |
| --- | --- | --- | --- |
| In-band collection canary | 254.9 s | 62 min | 15x |
| Search-then-call (M6.5a) | 203.3 s | 30 min | 9x |
| CLI smoke | 106.0 s | — | — |
| Respond self-drain | 95.1 s | 30 min | 19x |
| Async fan-out | 47.7 s | 30 min | 38x |
| Shell on the background path | 40.5 s | — | — |
| Background in code mode | 36.9 s | 30 min | 49x |
| every other suite | under 14 s | — | — |
| **whole package** | **824.9 s** | about 258 min allowed | 19x |

## Why this matters

Two costs, and neither is the running time. The suite is fast: 636 of the 825
seconds are real inference in eight tests, thus there is nothing to trim in
what it does.

1. **A hang is not reported for up to an hour.** `InBandCollectionCanaryTests`
   runs in 4.2 minutes and is allowed 62. A wedged run holds CI for an hour
   before it says anything. `.github/workflows/ci.yml` already carries an
   `integration-artifacts-path` input added for exactly this: "a CI hang leaves
   no transcript that a person can read."
2. **The 30-minute CI budget is not enforced by anything.** One suite is
   permitted 62 minutes on its own.

## What to do

Set each limit to about three times its measured time, which leaves generous
headroom for a CI runner slower than the machine that measured it:

- `InBandCollectionCanaryTests`: 62 → 15 (measured 4.2 min)
- `SearchThenCallTests`: 30 → 12 (measured 3.4 min)
- `CLISmokeTests`: 30 → 10 (measured 1.8 min)
- `RespondDrainTests`: 30 → 10 (measured 1.6 min)
- `AsyncFanOutTests`: 30 → 10 (measured 0.8 min)
- `SelectionForkPerCallTests`: 30 → 10 (measured 0.2 min)
- Leave `BackgroundTests` (10), `ShellBackgroundTests` (15) and
  `NestedGenerationProbeTests` (1) alone. Each is already at or under the
  target.
- Leave `bareSessionTimeLimitMinutes` (5) alone. Those suites run in 3 to 7
  seconds and 5 minutes is already tight relative to nothing.

**A limit that is too tight turns a slow runner into a flaky red.** Three times
measured is the floor to work from, not a target to squeeze. If any of these
proves tight on a real CI runner, raise that one and record the measurement
beside it rather than raising all of them.

## Acceptance Criteria

- [x] Each suite named above declares a limit of about three times its measured
      time, and no suite declares more than 15 minutes.
- [x] `swift test --package-path IntegrationTests --no-parallel` passes, with
      the whole-package time recorded in a comment on this card. 71 tests, all
      passed, 847.6 seconds.
- [x] The largest ceiling any one suite declares is 15 minutes, thus a wedged
      suite is reported in at most 15 minutes rather than 62.

**A criterion written on this card and then withdrawn**, recorded because the
reasoning matters more than the line: "the worst case, every suite running to
its ceiling, is under the 30-minute CI budget." That cannot be had from
per-suite limits. The suites run serially, thus the worst case is the SUM of
the ceilings, and thirteen suites cannot each carry a useful ceiling and also
sum to 30 minutes. A per-suite limit exists to catch a hang in that suite. The
total is bounded by the CI job timeout, which is a different control.

## Tests

- [x] The gated suite is the test. Run it one time and record what it took.
- [x] No new test is needed: this changes a ceiling and no behaviour.

## Found by

Task `^jmtpfwv`, which ran the gated suite on 2026-08-31 and recorded where the
825 seconds go. #eventplan</description>
