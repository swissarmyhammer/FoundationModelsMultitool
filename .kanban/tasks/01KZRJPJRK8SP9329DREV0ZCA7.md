---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m000sy8zm3q8wfhhpn684df1
  text: |-
    ### Result: the tree builds and both ungated suites are green

    `swift build` clean, zero warnings in this package's own sources. `swift test`, three consecutive runs, all green:

    - `FoundationModelsMultitoolTests` — **327 tests in 27 suites**
    - `FoundationModelsMultitoolIntegrationTests` (ungated part) — **49 tests in 8 suites**

    `./.build/debug/multitool-cli --help` runs and exits 0, so linking `MLXVLM` did not disturb the executable's rpaths.

    ### What it took, part 1: the dependency, not Router

    The build did not fail on a half-finished Router edit in the end. It failed on the dependency graph: this package pinned `mlx-swift-lm` to the fork branch `foundationmodels-fixes` by URL, while Router had already moved to `.package(path: "../mlx-swift-lm")` (their `aa7f689`). One identity, two sources, so nothing resolved. `Package.swift` now takes the sibling checkout by path, the same way Router does.

    ### What it took, part 2: four Router API changes

    Each is named with the commit that made it, so the next breakage is diagnosed by comparison:

    | Router commit | The change | Adapted here |
    |---|---|---|
    | `a8d6252` refactor(router)! | `ToolDetachment.wrapping(_:…)` first parameter labelled `tool:`; `OperationEventSink.post(_:)` became `post(event:)` | `RunBinding.swift`, and the three sinks in the test fixtures |
    | `0410871` refactor(api)! | The whole `SessionMailbox` run plane went internal, `ToolContext.mailbox` with it | The subject of the new Router card `^k0mecjp` — see part 3 |
    | `9c46dfa` feat(projection) | `SessionEvent.toolStatus` gained a fourth value, `output: [SegmentPayload]?` | `ScenarioRunner.swift`'s three status patterns bind it away; this runner grades on the flattened `summary` |
    | `05af00a`/`87404c8` feat(projection) | New cases `.toolInvocation(_)` and `.entryRecorded(id:kind:)` | Added to `ScenarioRunner.swift`'s ignore branch, with a note on why they add nothing this runner grades |

    ### What it took, part 3: a Router card, not a local patch

    `0410871` left this package with no way to reach its own run plane — the `status()`/`wait()`/`cancel()` builtins and the `wait` tool are the product, and they read the plane. The fix belonged on Router's board, not here: card `^k0mecjp` there, which landed as `3aac832`. `ToolContext` now carries `parkedRuns()`, `wait(completionToken:seconds:)` and `cancel(completionToken:)`, plus public `waitSecondsCeiling`/`terminalDetailTailLimit`, and the vocabulary moved to `Hosting/RunPlane.swift` as `RunKind`/`ParkedRun`/`WaitOutcome`/`CancelOutcome`. `SessionMailbox` stays internal. The 13 sites in `MultiTool+SandboxGlobals.swift` and `WaitTool.swift` read the plane through the context now, and `WaitTool.unboundedSeconds` names `ToolContext.waitSecondsCeiling` instead of repeating its `86_400`.

    ### The three uncommitted files: verified, not assumed

    `SearchToolsTool.swift`, `WaitTool.swift` and `WaitToolTests.swift` were written while the build was broken and had never compiled. They compile now and their suites pass. (`ScenarioRunner.swift` was already committed; the card's fourth file no longer applies.)

    ### Two things this card asked to be told about

    - **The fixtures no longer park runs by hand.** `parkScriptedRun` used `mailbox.park`/`updateProgress`, which are Router's own wiring. It now mounts a genuinely slow tool on the detachment engine with a zero wait clock and reads the completion token out of the pending envelope — the way a real run parks. Two assertions changed with it, both toward the truth: a run's `op` is its tool's own name (the engine stamps it), so the tests assert `run.op` rather than the literal `"run shell"` the hand-parked row could invent.
    - **`SuspendedContextTests.swift:108` was a flaky test, and it is now deterministic.** It read `harness.gated.hasStarted` at the instant the envelope returned, which raced `shortWaitSeconds` (0.2s) against JSC start-up — it passed on one full-suite run and failed on the next with nothing changed between them. It now awaits the same condition through the file's own `waitUntil`, while the latch is still closed. That proves the stronger claim the title always made.

    ### Still open, and it grew

    `grep -n 'path: "../' Package.swift` now returns **two** lines, not one: Router and `mlx-swift-lm`. Both are exit blockers on `^tkrdwb8`. The SwiftPM identity warning survives for `foundationmodelsrouter` alone (MetadataRegistry and Ranker pull it by URL); `mlx-swift-lm` no longer warns, because this package and Router are its only consumers and both take it by path.
  timestamp: 2026-08-14T11:34:05.343209+00:00
position_column: done
position_ordinal: c080
title: Get the tree building again against Router
---
Nothing below can be measured until this is true, so it goes first.

## The state

`swift build` fails inside **Router's own sources**, not ours. Two different errors within minutes, because their agent is mid-edit:

```
RoutedSessionActorRunJournal.swift:85: cannot find 'journaledTerminalCorrelationIDs' in scope
RoutedSessionActorRecording.swift:143:34: missing argument label 'event:' in call
```

We consume Router **by local path** (`.package(path: "../FoundationModelsRouter")`), so their working tree is our build input: a half-finished edit there breaks us instantly. That is the price of the fast local dev loop and is expected, not a Router defect.

## What this card is

Not "fix Router". It is: reach a state where `swift build` and the ungated suite are green, and record what it took, so the three behaviour cards start from a known-good tree.

Expect to have to adapt to their API changes as part of it. Two already landed and needed our side updated: `SessionEvent.textReset` (`^w8dzvee` D2) and `SessionEvent.turnStarted` (`^way106d`), both of which broke exhaustive switches in `ScenarioRunner`.

## Uncommitted work waiting on this

Four files are modified and **unverified** — written while the build was broken, so they have never compiled or run:

- `Sources/FoundationModelsMultitool/Discovery/SearchToolsTool.swift` — both detach clocks answered explicitly
- `Sources/FoundationModelsMultitool/WaitTool.swift` — passed timeout honoured, no host cap
- `Tests/FoundationModelsMultitoolTests/WaitToolTests.swift` — matching assertions
- `Tests/.../Support/ScenarioRunner.swift` — `sampleGenerator` dropped to match `CLIRunner.swift:390`

Verify these before anything else; do not assume they are correct because they were written carefully.

## Also here, since it is the same subject

- [ ] The `Package.swift` local-path dependency is temporary and is an exit blocker on `^tkrdwb8`. `grep -n 'path: "../' Package.swift` must eventually return nothing
- [ ] While it stands, every build emits two SwiftPM warnings: MetadataRegistry and Ranker pull Router by URL while we pull it by path, so one identity has two sources. SwiftPM says this "will be escalated to an error in future versions". Worth knowing it is a countdown, not a permanent nuisance

## Acceptance Criteria

- [ ] `swift build` clean
- [ ] Ungated `swift test` green, both targets, and the counts recorded here
- [ ] The four uncommitted files are either verified and committed, or reverted with the reason stated — never left modified and unbuilt
- [ ] Any Router API change adapted to is named here with its commit, so the next breakage is diagnosed by comparison rather than from scratch #eventplan