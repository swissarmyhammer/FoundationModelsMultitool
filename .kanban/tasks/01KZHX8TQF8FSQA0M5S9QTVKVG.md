---
assignees:
- claude-code
position_column: todo
position_ordinal: '8180'
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