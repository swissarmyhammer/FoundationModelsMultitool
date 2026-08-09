---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01kzkcp4pkkjcpe4wqn52hgx0x
  text: |-
    ### finish iteration 1 — clean

    - implement: changed — 1 file, `Tests/FoundationModelsMultitoolTests/SuspendedContextTests.swift`
    - test: green — ungated `swift test` on 5 consecutive runs, each 309 tests / 24 suites + 49 tests / 8 suites, zero failures
    - commit: 6d54aa4
    - review: clean — `review sha HEAD~1..HEAD` 0 findings / 9 validators; `review file SuspendedContextTests.swift` 0 findings / 9 validators
    - acceptance criteria: 4/4

    **This card's premise was wrong, and it was mine.** The title says the assertion is a wall-clock time limit. `:187` is `#expect(harness.gated.wasCancelled)` — a boolean on cross-task state, no clock in it. I wrote that diagnosis by analogy to `^hba675d` without reading the line.

    **The real defect** is a happens-before gap. `wasCancelled` is written by the gated tool's own task, in the `catch` that runs as `Task.sleep` throws `CancellationError`. Nothing orders that write against the terminal event the test observes just above it, so the test can sample the flag before the tool has written it.

    **The fix was already in the file.** `:154` waits with `waitUntil { gated.hasStarted }`, documented as "A synchronization point, not a timing assertion, so the deadline only bounds a genuine hang." `wasCancelled` was the one positive cross-task read still sampled; it now waits the same way. The other two reads at `:85` and `:109` are negative (`!wasCancelled`) — sampling is correct there — and `:108`'s positive `hasStarted` is already ordered by the `waitUntil` inside `makeHarness`. So the class is closed at one site, and that is the whole list.

    **Not a weakening.** `waitUntil` records an Issue and throws when the condition never holds. Control: dropping the `cancelledBox` write from the fixture fails the test with `condition never held within 10.0s` at `:369` — a better failure message than a bare false `#expect`. Fixture restored, `git diff` empty.

    **Left alone deliberately:** `:183`, `#expect(start.duration(to: .now) < Self.promptResponseBound)` — a real 3-second timing assertion, and the thing the card's title was reaching for. It is documented as discriminating a prompt settlement from a longer clock, its margin is 3s against a test that runs in about 1s, and no run today failed there. Changing it would be speculative. Flagged here rather than silently swept.

    **Reproduction: none.** 34 runs today — 14 full-suite, 20 targeted — 26 under 48–60 spinners plus concurrent swiftlint, the condition the original sighting was recorded under. Zero failures. So the fix rests on the ordering gap being real by construction, not on a reproduction. Sampling a value another task writes is a race whether or not it lost today; but anyone reading this should know the original 1-in-3 rate was not reproducible, and `^hba675d`'s fix landed today and changed suite contention, which may be why.

    Loop ran directly rather than through sub agents: the session hit its 200-agent cap before this card started.
  timestamp: 2026-08-09T13:51:36.147592+00:00
position_column: done
position_ordinal: ba80
title: '[Multitool] SuspendedContextTests'' cancellation teardown asserts a wall-clock time limit'
---
Split out of `^hba675d`. That card was filed for `promiseAllRunsToolCallsConcurrently`, then widened by a 2026-08-08 comment to cover three tests sharing one cause. `d693d77` fixed the Promise.all test and closed the card; this one is the remainder, carded so the widening is not lost.

## The defect

`Tests/FoundationModelsMultitoolTests/SuspendedContextTests.swift:187` — `harness.gated.wasCancelled`, in "cancel(completionToken) on a suspended snippet tears its context down within the time limit". Observed failing once in a full-suite run whose diff was **comment-only**, and passing **5/5 in isolation**. So it is contention under full-suite load, not a defect in the test's own logic.

Same cause as `^hba675d`: **an assertion on elapsed wall-clock standing in for "did this happen promptly"**. A budget with comfortable headroom on an idle machine has none on a loaded one.

## What `^hba675d` established that applies directly

The fix there restructured the claim to read the fixtures' own recorded instants instead of the turn's wall clock, and review measured why that works:

- Under full-suite load a turn stretched to 203.9 ms while the tool windows stayed at 150.9 ms — **the load lands in JSC startup, evaluation and marshalling, outside the recorded windows**. Anything measured across the whole turn absorbs that; anything measured inside the operation does not.
- Neither 256 spinners at load average 162 nor a 1-wide cooperative pool (`LIBDISPATCH_COOPERATIVE_POOL_STRICT=1`) moved the in-operation skew off 0.0–0.1 ms. Synthetic CPU load will **not** reproduce this; running inside the full parallel suite will.

So do not try to reproduce this with spinners. Run the full suite, repeatedly.

## What to do

Assert that the cancellation **reaches the context**, not that it did so inside N milliseconds. The property under test is teardown, and teardown either happens or it does not; the time limit is a proxy for it that machine load also moves.

Weigh, in order:

1. Await the teardown signal directly — have the harness expose completion the test can wait on, so the assertion is "it was cancelled", with the time limit demoted to a generous test-level guard against a true hang rather than the thing asserted.
2. If a duration must remain, measure it from the operation's own instants rather than the turn's, as `^hba675d` did.

Do **not** raise the limit and leave it, and do not add retry logic. `^hba675d` showed why raising is not a fix there: the concurrent-under-load and serialized-on-idle measurements already overlapped, so no constant separated the cases. Check whether the same is true here before assuming a bigger number would even work.

## Acceptance Criteria

- [x] The assertion no longer rests on a wall-clock budget for the whole operation, or the budget is demoted to a hang guard with the real claim asserted directly
- [x] The test still fails if cancellation never reaches the context — prove it with a temporary control that drops the cancellation, and report which assertion fired
- [x] No retry logic and no raised-and-left timeout
- [x] The full ungated suite runs green at or above 309 tests / 24 suites main and 49 / 8 integration, **run at least five times**, since this reproduces at roughly 1 run in 3 and a single green run is not evidence

## Note on reporting

`^hba675d`'s widening comment recorded that the suite is **usually green, not deterministically green** — roughly 1 run in 3 failed. That comment listed three failing *runs*, but only two distinct tests: run (a) was "`MultiToolExecution` suite, 1 issue", which is almost certainly run (c)'s Promise.all test reported without its name. So this card is the remaining one of **two** tests, not one of three. Any claim that it is done should name how many consecutive full-suite runs were observed, not report a single green run. #phase-1