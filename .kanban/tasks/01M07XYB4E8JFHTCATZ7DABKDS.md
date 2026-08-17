---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: NestedGenerationProbeTests cites the in-band canary's limit as three minutes, and it has not been three for two changes
---
Found while re-deriving the canary's ceiling under `^wnfzwxg`. Not caused by that change, but that change widens the gap, so it is recorded rather than fixed in passing.

## The stale line

`Tests/FoundationModelsMultitoolIntegrationTests/NestedGenerationProbeTests.swift`, in the `@Suite` limit comment:

    // Three minutes, the in-band collection canary's limit and for its reason:
    // this is one tool call plus one short nested turn, so a live run belongs
    // in the same 40-90 second band its peers finish in.

The clause "the in-band collection canary's limit" is false. That canary went 3 to 15 to 8 minutes across the investigation on `^wnfzwxg`, and `^wnfzwxg` has now re-derived it to ten. The probe's own three minutes has not moved.

## Why this is worth a card rather than a one-line edit

The sentence does two things at once. It states a **number** the two suites once shared, and it borrows a **reason**. Only the number went stale.

The reason it borrows is still sound for the probe and is stated in its own next clause: the probe exists to catch a deadlock, a deadlock is reported by the limit being reached, so the limit must sit near the expected runtime. The canary no longer shares that property — it is graded on the content of an answer, not on whether a clock fired, and its ten minutes is headroom over a measured worst run rather than a deadlock detector.

So the fix is not to update "three" to "ten". It is to cut the borrowed authority and let the probe's three minutes stand on the reason that is actually its own, which the comment already gives.

## Acceptance Criteria

- [ ] `NestedGenerationProbeTests` no longer cites the in-band collection canary's limit as its source
- [ ] Its three-minute limit is unchanged, and the deadlock-reporting reason it already states is what carries it
- [ ] `swift test` stays green

## Tests

- [ ] Ungated `swift test` green; no gated run needed, since the change is a comment
