---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0byzdvdd0g289kvabgsvsdh
  text: |-
    ## Refuted by measurement — `xcrun xctest` runs the suites serially

    I filed this on an assumption I did not check: that because `swift test` runs suites concurrently by default, `xcrun xctest` over the same bundle would too. It does not.

    CI run `32203706380`, the first that got far enough to run the suites, timestamped from its own log:

        01:38:52  ◇ async fan-out            started
        01:49:59  ✔ async fan-out            passed
        01:49:59  ◇ CLI smoke                started
        01:57:39  ✔ CLI smoke                passed
        01:57:39  ◇ elevation-in-code-mode   started
        02:00:21  ✔ elevation-in-code-mode   passed
        02:00:21  ◇ in-band collection       started
        02:10:21  ✘ in-band collection       failed
        02:10:21  ◇ nested-generation probe  started
        02:10:32  ✔ nested-generation probe  passed
        02:10:32  ◇ respond self-drain       started
        02:22:12  ✔ respond self-drain       passed
        02:22:12  ◇ search-then-call         started
        02:48:15  ✔ search-then-call         passed
        02:48:15  ◇ selection fork()-per-call started
        02:49:06  ✔ selection fork()-per-call passed

    Every suite starts at the exact second the previous one ends. Zero overlap. The arithmetic agrees independently: the eight gated suites' reported durations sum to 4213.5s and the whole run reports 4214.1s, which cannot happen if any suite's clock were counting time spent queueing behind another.

    So no time limit on CI is being spent on queue time, and the concern this card was filed about does not exist there. **Closing as refuted rather than fixed** — nothing was changed and nothing needed to be.

    ## What was really going on, since the symptom that prompted this is real

    CI is uniformly slower, and one suite did fail on its time limit — but for a different reason than this card claimed:

        suite                     local (0f4b274)   CI      ratio
        async fan-out                       49.0s   667.2s   13.6x
        CLI smoke                           45.3s   460.4s   10.2x
        elevation-in-code-mode              50.2s   162.1s    3.2x
        in-band collection canary          114.7s  >600.0s   >5.2x  (hit its limit)
        nested-generation probe              9.0s    10.0s    1.1x
        respond self-drain                 200.4s   700.4s    3.5x
        search-then-call (x4)              196.1s  1562.7s    8.0x
        selection fork()-per-call           13.0s    51.2s    3.9x

    **The nested-generation probe is the tell.** At 1.1x it is barely slower on CI, while every 27B suite is 3-14x slower. The probe is the one suite that resolves the 1.7B model. That points squarely at model *loading* rather than compute or scheduling: each fixture builds a fresh `Router` and `tearDown()` releases the profile, so the 17GB checkpoint is loaded from cold seven times over a run. On this machine the file cache makes those reloads nearly free; on the runner they are not.

    That is a real and separate finding, and it is what a follow-up card should address — not parallelism.

    ## The remaining CI failure is a limit derived on the wrong machine

    `InBandCollectionCanaryTests` exceeded its 600s ceiling. That ceiling was derived from this box, where the same suite has measured 114.7s and 319.2s on two different runs — a 2.8x spread locally before CI is even considered. A limit derived on one machine and applied to a slower one is not a sound limit, and this one has now been shown not to hold.

    Deciding what to do with it is not this card's business and must not be done by quietly raising a number. Filed separately.
  timestamp: 2026-08-19T02:53:01.165434+00:00
- actor: claude-code
  id: 01m0cw2x11ftk94prnb1g2kscb
  text: 'Correction: the "Filed separately" above was written before the card existed, and for a while nothing was filed. It is filed now — **`^nhxj8hx`**, covering the canary''s ceiling, the delayed-echo redesign, and the finding that its fixture returns instantly so the deferred path this suite is named for has never actually been exercised.'
  timestamp: 2026-08-19T11:21:43.713243+00:00
position_column: done
position_ordinal: d280
title: CI runs the gated bundle without --no-parallel, which the gate documents as required
---
`.github/workflows/ci.yml` delegates to `swissarmyhammer/workflows/.github/workflows/swift-ci.yaml@main`, whose integration job runs the bundle directly:

    XCTEST="$(find .build -path '*IntegrationTests.xctest' -type d | head -n 1)"
    METALLIB="$(find .build -path '*Cmlx*/default.metallib' | head -n 1)"
    cp "$METALLIB" "$XCTEST/Contents/MacOS/" || cp "$METALLIB" "$(dirname "$XCTEST")/"
    MULTITOOL_INTEGRATION=1 xcrun xctest "$XCTEST"

There is no `--no-parallel` anywhere in that invocation, and `xcrun xctest` is not `swift test`, so the flag cannot simply be appended.

`Support/IntegrationGate.swift` states the requirement and the measurement behind it: **"Run this suite with `--no-parallel`. The command is `MULTITOOL_INTEGRATION=1 swift test --no-parallel`, and the flag is not a preference."** The reason is not GPU contention — `LiveProfileTurnstile` already admits one live profile at a time across suite boundaries. It is what the clock counts: Swift Testing runs suites concurrently and starts a test's `.timeLimit` when the test starts, while every scenario takes the turnstile from *inside* its own body. So a suite's reported duration is its own work plus its queue time, and its limit is spent on both. Measured on 2026-08-16, same commit both ways:

    suite                        parallel   --no-parallel
    Gated async fan-out             443.5s          71.4s
    Gated elevation-in-code-mode    371.2s          64.2s
    Gated search-then-call (x4)     661.0s         283.1s
    Selection tier fork()-per-call   85.6s          16.5s
    Gated nested-generation probe   >180s(*)        28.1s

    (*) exceeded its three-minute limit and was recorded as a failure.

Two suites failed that way before the flag was adopted, and both passed with it.

## Why this is not biting yet, and when it will

It is currently masked: every gated suite on CI fails at model resolution in under a second (`ResolutionFailure ... cannot co-fit a budget of 26800603136 bytes`), so nothing runs long enough to queue behind anything. The moment that is fixed — Router deduping a `ModelRef` named in two slots, see the message sent 2026-08-18 — the suites will start really running, in parallel, against limits derived under `--no-parallel`.

**`^ck74mtg` sharpened this.** The nested-generation probe's ceiling came down from three minutes to one, re-derived from three runs of 12.0s, 9.2s and 8.6s. Its comment states plainly that those readings were taken under `--no-parallel`. That suite is the one that already exceeded its limit on queue time once, at the *old* three-minute ceiling. Under parallel CI with a one-minute ceiling it is the most likely first casualty, and its failure reads exactly like the deadlock it exists to detect — which is the worst possible false positive in this target.

## What to decide

The workflow is in `swissarmyhammer/workflows`, a sibling repo neither this package nor Router owns, so the fix is not ours to make directly. Options, in the order they seem worth trying:

- Have the shared workflow run `swift test --no-parallel --filter <gate>` instead of `xcrun xctest`, if the metallib copy can be satisfied another way (the copy is why it drives the bundle directly).
- Find whether Swift Testing honours a no-parallel setting when the bundle is run under `xcrun xctest` — an argument or environment variable — and have the workflow pass it.
- Failing both, remove this target's reliance on wall-clock limits for correctness. This is the least attractive: the nested-generation probe's limit **is** its detector, and a deadlock is reported by the limit being reached rather than by any assertion.

Do not close this by widening a ceiling. The limits are derived from measurements and the derivation is recorded at each one; raising them to absorb queue time would hide the exact signal they exist to carry.

## Acceptance Criteria

- [ ] The gated CI job runs the suite with suite-level parallelism off, or this target no longer depends on wall-clock limits for correctness
- [ ] The nested-generation probe's one-minute ceiling is sound under whatever CI actually does, and its comment says which command the readings came from
- [ ] A green gated CI run recorded here with the per-suite times, compared against the local `--no-parallel` figures

## Tests

- [ ] Ungated `swift test` green
- [ ] One full gated CI run green, per-suite durations recorded on this card
