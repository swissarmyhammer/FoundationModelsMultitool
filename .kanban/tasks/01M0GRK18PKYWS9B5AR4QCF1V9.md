---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: ElevationTests passes CI with 14 seconds of margin against its 30-minute limit
---
CI run `32392350928` (push `950ad13`, 2026-08-20), job `96504690907`: the suite "Elevation-in-code-mode scenario (phase-1 exit)" **passed**, and its time was `1785.670 seconds` against its declared `.timeLimit(.minutes(30))` of 1800 seconds. The margin is 14.33 seconds, which is 0.8 percent of the budget.

The scenario itself recorded `RESULT [elevationInCodeMode] elapsed=1777.7s toolCalls=23 toolOutputs=23 pendingEnvelopes=21 tokens=out:1916 failedCalls=0` with the correct answer, so the run was healthy. It was only slow.

## Why this is a defect

A suite that consumes 99.2 percent of its ceiling on a healthy run fails on the next run that is a little slower. Worse, that failure prints `Time limit was exceeded: 1800.000 seconds` at `ElevationTests.swift:29` — the same line and the same message as the unexplained zero-activity stall of card `^hht0009`. The two causes then become impossible to tell apart from the CI log alone, and `^hht0009` is still open on its cause.

## The measurements, which do not agree

| Where | Time | Tool calls | Card |
|---|---|---|---|
| Dev box | 51.79s | not recorded | `^dwzkfzx`, 2026-08-19 |
| Dev box | 643.687s | 24 | `^hht0009`, 2026-08-20 |
| CI | 1785.670s | 23 | this card, 2026-08-20 |

The spread between the two dev-box runs alone is more than 12 times, on the same machine and the same scenario. No CI slowdown factor explains that, so a ceiling derived only from a CI-slowdown multiple is not trustworthy for this suite.

## What

1. Find why the same scenario takes 51.79s on one run and 1785.670s on another. Read the Router transcripts — the recordings now survive under `IntegrationTests/.build/recordings`, and card `^9gkbbvq` made CI upload them as the `integration-artifacts` artifact, so a CI transcript is available from any run after `76c7890`. Compare a fast transcript against a slow one: tokens generated, tool rounds, retries, context growth, and time per round.
2. Remove the cause of the variance where it is in this repository's code or fixtures. If the cause is in Router or in the backend, name it with evidence and route a card to that repository — do not edit a sibling package here.
3. Only then re-derive the ceiling by the method of card `^nhxj8hx`, from real measurements with a stated margin. Do not raise the limit before step 1, because a raised limit hides both this variance and the stall of `^hht0009`.

## Acceptance Criteria

- [ ] The cause of the 30-times run-time spread is named on this card with evidence from at least one fast and one slow transcript.
- [ ] The cause is removed, or routed to the repository that owns it with the evidence recorded here.
- [ ] The `.timeLimit` of the suite is re-derived by the method of `^nhxj8hx`, with the measurements and the margin written here. No retry loop.
- [ ] A CI run shows the suite passing with a margin that the derivation states.

## Tests

- [ ] Root `swift test` green.
- [ ] One CI integration run with the suite green, run id and suite time recorded here.

## Related

- `^hht0009` — the unexplained zero-activity stall of the same suite. Different shape: zero tool calls and no fragment for 1763s. Keep the two apart.
- `^9gkbbvq` — made CI keep the recordings, which gives this card its evidence.
- `^nhxj8hx` — holds the ceiling-derivation method.