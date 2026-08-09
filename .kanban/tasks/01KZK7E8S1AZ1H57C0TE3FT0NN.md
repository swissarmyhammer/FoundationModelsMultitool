---
assignees:
- claude-code
position_column: todo
position_ordinal: '8280'
title: '[Multitool] Negative assertions on hint wording pass hollowly after a reword'
---
Found by the review sweep on `^w0rxeg7`, which deliberately raised no finding for it: the sites are pre-existing test code, which the review skill's blanket exception forbids raising findings against, and they are not `ResultRenderer` wording, so they fall outside that card. Carded here so the observation is not lost.

## The defect

`Tests/FoundationModelsMultitoolTests/UnknownToolHintTests.swift:248` and `:375` assert:

```swift
#expect(!output.contains("does not exist"))
```

`"does not exist"` is live shipped wording, at three sites in `Sources/`:

- `Discovery/UnknownToolHint.swift:244` — `"tools.\(failedPath) does not exist, and nothing close matches. "`
- `Discovery/UnknownToolHint.swift:259` — `"tools.\(failedPath) does not exist. \(instruction)\n\n"`
- `Discovery/SampleSnippet.swift:339` — `"That snippet calls tools.\(invented), which does not exist. "`

The claim each test means to make is **"the no-match branch was not taken"**. What it actually proves is **"this exact phrase is absent"**. Reword the hint and the assertion becomes vacuously true — it passes whether or not the branch was taken, forever, silently.

## Why this is the inverse of `^w0rxeg7`, not the same bug

`^w0rxeg7` removed hand-written copies of shipped wording from *positive* assertions. Those were the benign direction: a positive `contains` on stale wording fails loudly the moment the product is reworded, so the staleness announces itself. A *negative* `contains` degrades in the opposite direction — it stops testing anything and reports success. That is strictly worse, and it is why this is worth its own card rather than being folded into the sweep.

The review sweep also found benign hand-written hint copies at `UnknownToolHintTests.swift:69, 87, 132, 152, 193, 216`, `SampleSnippetTests.swift:149`, and `SuspendedContextTests.swift:158` (which copies `MultiTool+Elevation.swift:144`'s cap message). Those are all positive assertions and fail loudly, so they are noted, not scoped in.

## What to do

Make each negative assertion name the branch rather than the phrase. Options, in order:

1. Assert on the branch's own identity rather than its text — if the hint type can report which branch produced it (near-match vs no-match), assert that. The claim then survives any reword.
2. If the text must be the signal, read it from the one place it is written rather than copying it, the way `^w0rxeg7` did for `ResultRenderer`'s summaries: give `UnknownToolHint` an internal member holding the no-match wording and have the tests negate against that. A reword then moves the assertion with it.

Prefer 1. Option 2 keeps a text-shaped test but at least makes it impossible for the assertion and the product to disagree.

Check `Tests/` for other `!...contains(` assertions against shipped wording while you are in there — a finding shows one example of a cause, and these two were found only because a sweep went looking.

## Acceptance Criteria

- [ ] Neither `:248` nor `:375` can pass hollowly after a reword of the no-match hint — prove it by rewording the shipped wording and confirming the tests still discriminate, then restore
- [ ] Every other `!...contains(` assertion in `Tests/` that names shipped wording is enumerated and either fixed the same way or recorded with a reason it is safe
- [ ] No weakened assertion, no shipped behaviour change
- [ ] Ungated `swift test` green at or above 309 tests / 24 suites main and 49 / 8 integration, run more than once

## Note

Known load-sensitive flake `^9qtvkvg` (`SuspendedContextTests.swift:187`) fires at roughly 1 run in 3 under full-suite contention. Rerun before calling the suite red. #phase-1