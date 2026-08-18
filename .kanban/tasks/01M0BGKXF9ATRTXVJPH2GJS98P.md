---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
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
