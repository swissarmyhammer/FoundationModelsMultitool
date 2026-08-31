---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m173keppedkh9j9b3y4hpvsj
  text: |-
    ### finish iteration 1 — stuck
    - The diagnosis in the description is wrong, and the correction changes what this task is. The failure is not local machine state. The Router removed a public symbol that this package calls.
    - `6f0b2a8 refactor(api): demote the mistakenly public Hosting plumbing to internal` changed `public enum ToolMounting` to `enum ToolMounting` in `Sources/FoundationModelsRouter/Hosting/ToolMounting.swift`. The symbol has a consumer outside that package: `Sources/FoundationModelsMultitool/Invocation/RunBinding.swift:148` calls `ToolMounting.makeWrapped(...)`. Five more sites name it in documentation comments: `Capabilities/Shell/Execute.swift:46`, `Capabilities/Shell/Execute.swift:112`, `Surface/APISurface.swift:61`, `MultiTool+Background.swift:8`, `Invocation/RunBinding.swift:110` and `Invocation/RunBinding.swift:157`.
    - Evidence: at `760ae89`, which `Package.resolved` pins, the file declares `public enum ToolMounting`. At `origin/main` of the Router, which is `b26ee0f`, it declares `enum ToolMounting`. `760ae89` is an ancestor of `b26ee0f`.
    - Thus the root build is not safe, it is only lucky. The pin is declared as `branch: "main"`, so the next `swift package update` takes `b26ee0f` and the ROOT package fails to build, and not only the nested `IntegrationTests` package. The edit link did not cause the failure. It read the newer Router code first and showed the break early.
    - The Router working copy holds no source edit now. Only board files are dirty there, and it is 4 commits ahead of `origin/main`.
    - Asked the `foundationmodelsrouter-46` session which way to go: make `ToolMounting.makeWrapped` public again, or name a supported API to call instead. This package cannot decide it, because the symbol belongs to the other package.
    - next: wait for that answer. Do not remove the edit link yet — removing it hides the break behind the stale pin and leaves the pin unable to move.
  timestamp: 2026-08-29T15:53:21.366439+00:00
- actor: claude-code
  id: 01m1avp7jz54m0j1b2yv9d5e27
  text: |-
    ### implement — changed

    The nested package builds. Commit `8df2ccf`.

    - **Criterion 1 met.** `swift build --package-path IntegrationTests --build-tests` gives "Build complete!".
    - **Criterion 2 met.** The edit link is removed with `swift package unedit`, the `IntegrationTests/Packages/` directory is gone, and `IntegrationTests/Package.resolved` holds `foundationmodelsrouter` at branch `main`, revision `475befba6`.
    - **Criterion 3 not attempted.** The gated suite drives real models. It is expensive, and running it is a separate decision from making the package build.

    Four changes were needed, each against a published API of the Router:

    1. `swift package unedit FoundationModelsRouter`, then `update`. The nested package had also pinned an older Router (`f31f453`) and a stale `FoundationModelsExtras`, which made the Router itself fail to compile; a full nested `update` fixed both.
    2. `ShellBackgroundRunner.swift` reads `TranscriptEvent.operationEvents`, which the Router published in `b000a32` for this fixture. It names neither `OperationEventSegment` nor the case shape of a segment now.
    3. `LiveRouterFixture.swift` reads `TranscriptEvent.merged(under:)`, published in `1680422`, in place of the internal `MergedTranscript`.
    4. The resolve diagnostic drops the context window and the per-candidate charge, because `RoutedLLM.resolution` is `package`-protected now. That line is a diagnostic and never an assertion. It is also built in named pieces, because one chained interpolation of that length times the type checker out.

    The task description said the cause was local machine state and not a file of this repository. That was wrong, and the correction is recorded in the earlier comment: the Router had demoted symbols this package named, and the edit link only made the break visible early.

    next: nothing on this card. Criterion 3 is a separate decision for a person.
  timestamp: 2026-08-31T02:52:01.503741+00:00
position_column: done
position_ordinal: ffa680
title: The nested IntegrationTests package builds against an edited Router working copy, and cannot compile
---
## What
`swift build --package-path IntegrationTests --build-tests` fails today:

```
Sources/FoundationModelsMultitool/Invocation/RunBinding.swift:148:27:
error: cannot find 'ToolMounting' in scope
```

The root package builds and tests clean. Only the nested package fails. The cause is local machine state, and not a file of this repository.

`IntegrationTests/.build/workspace-state.json` holds `FoundationModelsRouter` in the **edited** state:

```
{"name": "edited", "path": "/Users/wballard/github/swissarmyhammer/FoundationModelsRouter"}
```

`IntegrationTests/Packages/FoundationModelsRouter` is a symlink to that folder, made on 2026-08-26. Thus the nested package compiles the root library against the sibling **working copy** of Router, and not against the pinned remote revision. `IntegrationTests/Package.resolved` therefore holds no `foundationmodelsrouter` pin, and `IntegrationTests/.build/checkouts/` holds no Router checkout.

In that working copy, `Sources/FoundationModelsRouter/Hosting/ToolMounting.swift` declares `enum ToolMounting {` — internal, not `public` — so the root library cannot name it. The working copy also carries an uncommitted change to `Router.swift`, thus another session is at work in it now.

The root package resolves Router from the remote at revision `760ae89`, where the type is public, and every one of the 1312 unit tests passes.

`Package.swift` of this package records this failure mode for task `^ev0zca7`: "a published branch is a *snapshot*, and a working copy is whatever another session happens to have saved. Building against a working copy is how this package spent a morning failing on someone else's half-finished edit."

## Why this is its own task
The fix removes another session's edit link, and that session is at work in the Router folder now. Do not remove the link while that work is in flight.

## What to do
- Ask first whether the Router edit link is still wanted. If it is not, run `swift package --package-path IntegrationTests unedit FoundationModelsRouter`, then `swift package --package-path IntegrationTests resolve`.
- Build again: `swift build --package-path IntegrationTests --build-tests`.
- If the edit link is wanted, wait until the Router work lands on `main` and the type is public.

## Acceptance Criteria
- [x] `swift build --package-path IntegrationTests --build-tests` completes with no error. Done on 2026-08-31, commit `8df2ccf`.
- [x] `IntegrationTests/Package.resolved` holds a `foundationmodelsrouter` pin. Done on 2026-08-31: branch `main`, revision `475befba6`. The edit link is removed and `IntegrationTests/Packages/` is gone.
- [x] The gated suite runs: `swift test --package-path IntegrationTests --no-parallel`. Done on 2026-08-31: **71 tests in 17 suites, all passed, 824.9 seconds**, against the Router's `main` at `5a8075b`.

## What the gated run proves

The four `SearchThenCallTests` scenarios pass against a real model, which is
the coverage that says code-mode tools are discoverable and callable:

| scenario | seconds |
| --- | --- |
| single-call weather | 35.5 |
| compose and chain, `getTrip` to `getWeather` to warmest | 51.3 |
| discovery among distractor tools | 55.8 |
| repair, however many attempts it takes | 34.7 |

## Where the 825 seconds go

Eight tests take 636 seconds, which is 77 percent of the run:

```
192.1s  the delayed echo's value comes back through its handle, collected in band
 95.1s  respond answers from what the backgrounded run returned
 81.4s  discovery scenario still names the warmest trip city among the distractors
 63.5s  the live demo attaches a stdio MCP server, lists its verbs, and still answers
 62.7s  the model collects its own background run
 51.6s  compose and chain scenario
 47.7s  async fan-out scenario
 42.5s  the live demo succeeds and prints a non-empty final answer
```

Each drives real inference, thus the time is generation and not overhead.

## Two costs that must not be optimized away

Both are deliberate, both are documented with a measurement, and both protect
the reliability signal this suite exists to give.

1. **A fixture resolves per scenario and releases at teardown.** Sharing one
   would be faster and would let a prompt cache carry between scenarios. The
   measured failure was a model that narrated a tool call it never made,
   because its context already held one. That is a false pass of exactly the
   claim these tests make.
2. **`--no-parallel`.** Measured at 661 seconds parallel against 852 serial,
   thus serializing costs about 190 seconds. It buys correct attribution:
   under parallel runs a tight time limit fires on queueing rather than on the
   scenario, a failure reads like a hang, and it lands on whichever suite holds
   the tightest ceiling. Two suites failed that way before the flag.

## A speed and simplicity opportunity, for its own card

50 of the 71 tests need no model at all: `ScenarioFailureModeTests` (22),
`ScenarioFixtureTests` (20) and `ScenarioGradingTests` (8) name no
`LanguageModelSession`, no `SystemLanguageModel` and no live fixture. They test
the harness itself, and they run only when a person runs the gated suite.

They cannot move as things stand, and the reason is also the simplicity
problem: `Support/ScenarioRunner.swift` is 1704 lines and holds both the
grading logic, which is pure, and the live-model driving, which is not. Split
it and those 50 tests join the 6.5-second root suite, while the gated package
becomes only what a gated package is for. `Support/ScenarioFailureModes.swift`
(253 lines, no live reference) and `Support/LiveRouterFixture.swift` (663
lines, live only) show that the split is the file's natural shape already.

## What the diagnosis above got wrong

The description says the cause is local machine state and not a file of
this repository. That is wrong. The Router had demoted symbols this package
named — `ToolMounting`, `SessionMailbox`, the `OperationEventSink` typealias,
`MergedTranscript`, `OperationEventSegment` and `RoutedLLM.resolution` — and
the edit link only made the break visible before a resolve would have found
it. The fix was to take the Router's published readers, not to remove a link.

## Found by
Task `^tq2qzga`, the phase-4 exit, on 2026-08-28. That task changed no manifest and no source of the library, thus it did not cause this failure. #eventplan #phase-4 #eventplan-phase-4