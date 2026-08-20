---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: 'ElevationTests hangs on CI: 30 minutes, zero tool calls, empty reply'
---
CI run `32294279325` (push `563a483`, 2026-08-19): the suite "Gated elevation-in-code-mode scenario (phase-1 exit)" failed its `.timeLimit` — `Time limit was exceeded: 1800.000 seconds` at `ElevationTests.swift:29`, plus two `check.held` failures at `ScenarioRunner.swift:805`. The scenario record shows a hang, not a slow pass: `RESULT [elevationInCodeMode] elapsed=1793.2s toolCalls=0 toolOutputs=0 pendingEnvelopes=0 reply=""`. The model produced nothing for 30 minutes. The same suite passed on this dev box in 51.79s (card `^dwzkfzx`, 2026-08-19), and every other suite in the same CI run passed — 62 tests in 11 suites, 3 issues, all from this one scenario. The reworked in-band collection canary passed on CI in the same run.

## What

Find and remove the cause of the zero-activity hang. Known facts to start from:
- `toolCalls=0` means the turn hung before the first tool call — in generation, in model load, or in a gate — not in the deep-scan fixture (its delay is 8s) and not in `wait`.
- CI is uniformly ~6x slower than the dev box, which predicts ~5–6 minutes for this suite, not 30.
- The suites run `--no-parallel`, so nothing else held the resident profile during the run.
- The suite name still says "Gated" — rename it while in the file (see `^820xc9z` vocabulary rules).

Investigate the Router transcript for the run if CI kept one, or reproduce locally under memory pressure. Fix the failure class structurally — no retry, no time-limit raise (see `^nhxj8hx`'s ceiling-derivation method if the limit itself proves wrong after the hang is fixed).

## Acceptance Criteria

- [ ] The cause of the zero-activity hang is named on this card with evidence
- [ ] The fix is structural — no retry loop, no raised limit to mask the hang
- [ ] The suite name no longer says "Gated"

## Tests

- [ ] `swift test --package-path IntegrationTests --no-parallel --filter Elevation` green locally, time recorded here
- [ ] A green CI integration job containing this suite, run id and suite time recorded here

## Workflow

- Use `/tdd` where a regression test can hold the cause; a hang found in fixture or harness code gets a failing test first.