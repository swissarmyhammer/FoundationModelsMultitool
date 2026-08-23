---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0nsn1h222595z9kj6ekd55r
  text: |-
    ### Research

    Sources read: `../FoundationModelsShelltool/Sources/ShellTool/CommandSandbox.swift` (201 lines) and `SandboxPreflight.swift` (157 lines), plus the three sibling test files.

    Findings that shape the port:

    1. The sibling tests cannot come across as they stand. `SandboxPreflightTests`, `SandboxSurfaceTests` and `SandboxPublicSurfaceTests` each drive `SeatbeltSandbox`, `SeatbeltSandboxError`, `ShellRunner`, `ShellContext` and `ShellTool.make`. None of those is in this package: `Capabilities/Shell/` holds `ShellState`, `ShellDotfolder`, `OutputChunkStream` and `OutputBuffer` only, and the seatbelt implementation is the next card (`^3qhrkey`). The tests therefore port the half the seam itself supports — the protocol, the returned value, the inherited default `preflight`, the identity sandbox, the canary result, the live spawn, and the gate.

    2. The import boundary decides which test file holds what. `SandboxSurfaceTests.swift` must import the module PLAINLY (no `@testable`), because that is the whole proof that `CommandSandbox`, `SandboxedInvocation` and its initializer are genuinely public — acceptance criterion 2. `UnconfinedSandbox` stays `internal`, thus its tests stand in `SandboxPreflightTests.swift`, which imports with `@testable`.

    3. Two numbers in the source must get a name or one spelling. `canaryStandardErrorLimit = 64 * 1024` becomes `65_536`, and the bare `128` of `128 + signal` becomes a named constant. `ShellState.swift` already writes `1_000_000_000_000_000` as one number, thus this matches the neighbours.

    4. Doc comments in the source name `ShellTool.make(sandbox:)`, `ShellRunner.runBody`, `ExecuteCommand`, `SeatbeltSandboxError`, `ShellContext.connecting(_:)` and `ProcessRegistry`. No such name is in this package. Each doc comment states the same contract without a name that is not there.

    5. No new dependency. `Subprocess`, `Synchronization` and `System` all reach the library target today, and `Package.swift` already names `SandboxPreflight` as a consumer of `Subprocess`.

    6. The tree is clean. Only `.kanban/` files are untracked, and they are this session's board records.
  timestamp: 2026-08-22T22:32:22.306718+00:00
- actor: claude-code
  id: 01m0nt3ea6vymddkkz68tx3a8p
  text: |-
    ### Implementation

    Order of work, `/tdd`:

    1. Wrote the two test files first. RED is on record: `swift build --build-tests`
       answered `cannot find 'SandboxedInvocation' in scope`, `cannot find type
       'CommandSandbox' in scope`, and `value of type 'RearrangingSandbox' has no
       member 'preflight'` — the feature was absent, and no typo caused it.
    2. Wrote the two source files. GREEN: 13 new tests pass, and the whole suite is
       480 tests in 40 suites.

    What changed against the Shelltool source, and why:

    - `canaryStandardErrorLimit` is `65_536`, and not `64 * 1024`. One number, one
      spelling, as `ShellState.attosecondsPerMillisecond` already writes it.
    - `128` in `128 + signal` is now `signalExitCodeBase`, a named private constant
      with its own doc comment. The value does not move.
    - Each doc comment that named `ShellTool.make(sandbox:)`, `ShellRunner`,
      `ExecuteCommand`, `SeatbeltSandboxError`, `ShellContext.connecting(_:)`,
      `ProcessRegistry` or `profileOverride` now states the same contract with no
      name that is not in this package.
    - `CommandSandbox.swift` needs no import at all. `SandboxPreflight.swift`
      imports `Subprocess`, `Synchronization` and `System`, exactly as the source
      does. Neither file names `Operations`.

    Test coverage of each ported declaration:

    | declaration | pinned by |
    |---|---|
    | `SandboxedInvocation`, its `init` and both properties | `SandboxSurfaceTests`, plain import |
    | `CommandSandbox.wrap`, through the witness table | `SandboxSurfaceTests` |
    | `CommandSandbox.preflight`, the requirement | `SandboxSurfaceTests` |
    | the inherited default `preflight` | `SandboxSurfaceTests` |
    | `UnconfinedSandbox` | `SandboxPreflightTests` |
    | `CanaryGate.passOnce`, one time for each gate | `SandboxPreflightTests` |
    | `CanaryGate.passOnce` under callers that overlap | `SandboxPreflightTests` |
    | a canary that failed does not latch | `SandboxPreflightTests` |
    | `CanaryResult`, `CanarySpawn`, `liveCanarySpawn` | `SandboxPreflightTests`, three live spawns |

    Notes for the next agent, on `^3qhrkey`:

    - `UnconfinedSandbox` is `internal` and has no production caller yet. The runner
      that will hold a sandbox lands later in phase 2. Each test target counts as a
      caller for periphery, thus the declaration is not dead.
    - The signal test runs `/bin/sh -c "kill -9 $$"`. `SIGKILL` cannot be caught,
      thus the shell always ends by the signal, and the test is not statistical.
      `SIGTERM` was rejected for that reason.
    - The two test files must keep their import forms. `SandboxSurfaceTests`
      imports plainly, and that plain import IS the proof the public names are
      public. `SandboxPreflightTests` imports with `@testable`, thus it holds each
      internal name.
  timestamp: 2026-08-22T22:40:14.150828+00:00
- actor: claude-code
  id: 01m0nt3sn0w8kfzxh5k4b64q85
  text: |-
    ### implement — changed
    - evidence: 4 files — Sources/FoundationModelsMultitool/Capabilities/Shell/CommandSandbox.swift, Sources/FoundationModelsMultitool/Capabilities/Shell/SandboxPreflight.swift, Tests/FoundationModelsMultitoolTests/SandboxSurfaceTests.swift, Tests/FoundationModelsMultitoolTests/SandboxPreflightTests.swift. `touch Sources/FoundationModelsMultitool/Capabilities/Shell/*.swift && swift build --build-tests` reports the known mlx-swift_Cmlx.bundle warning and nothing else. `swift test --filter Sandbox` passes 47 tests in 4 suites. `swift test` passes 480 tests in 40 suites, 0 failures.
    - next: /review
  timestamp: 2026-08-22T22:40:25.760909+00:00
- actor: claude-code
  id: 01m0ntedhs03vm0avrpmn26gff
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit 2103bc6), 4 files reviewed, 0 not reviewed. counts: 0 findings, 0 confirmed, 0 refuted; 7 validators attempted, 0 failed, 0 skipped. The 7 that match a Swift diff are code-hygiene, code-security, completeness, duplication, reuse, swift, test-integrity. Each acceptance-criterion and test box in the description is already `- [x]`, and no prior `## Review Findings` section is on the card. Thus the card moves to Done.
    - next: `^3qhrkey` — the SeatbeltSandbox implementation, which this card unblocks.
  timestamp: 2026-08-22T22:46:13.817508+00:00
- actor: claude-code
  id: 01m0ntfccy12gabk56r753zyyz
  text: |
    ### finish iteration 1 — clean
    - implement: changed — 4 new files (Capabilities/Shell/CommandSandbox.swift, Capabilities/Shell/SandboxPreflight.swift, SandboxSurfaceTests.swift, SandboxPreflightTests.swift)
    - test: green — a forced rebuild reports no compiler warning; `swift test` gives 480 tests in 40 suites passed, 0 failures, 0 skipped
    - commit: 2103bc6 — feat(shell): add CommandSandbox seam and SandboxPreflight
    - review: clean — 0 findings, 7 validators, 0 failed. The concurrency and the process handling of the canary spawn, the two departures from the sibling, the judgement on which sibling tests could not port, and the plain (not `@testable`) import of SandboxSurfaceTests each raised nothing.
    - next: done. This unblocks `^3qhrkey`, the SeatbeltSandbox implementation.
  timestamp: 2026-08-22T22:46:45.406816+00:00
depends_on:
- 01M0NAF9VBHGY2DFNM5PFA3DER
position_column: done
position_ordinal: e280
title: Port the CommandSandbox seam and SandboxPreflight
---
## What

eventplan.md does not name the sandbox in the phase 2 scope. The decision of
2026-08-22 is to move it, so that nothing is lost when the Shelltool repository
is archived.

Port the sandbox seam first. The seatbelt implementation follows in its own
task.

- Create `Sources/FoundationModelsMultitool/Capabilities/Shell/CommandSandbox.swift`
  from `../FoundationModelsShelltool/Sources/ShellTool/CommandSandbox.swift`
  (201 lines). This is the `CommandSandbox` protocol and its `wrap(...)`
  contract.
- Create `Sources/FoundationModelsMultitool/Capabilities/Shell/SandboxPreflight.swift`
  from `../FoundationModelsShelltool/Sources/ShellTool/SandboxPreflight.swift`
  (157 lines).
- Keep the default of no confinement. A capability that is built with no
  sandbox confines nothing.
- Do not import `Operations`.

## Acceptance Criteria

- [x] `CommandSandbox` and `SandboxPreflight` are in
      `Sources/FoundationModelsMultitool/Capabilities/Shell/`.
- [x] The `CommandSandbox` protocol is public. A host supplies its own
      conformer.
- [x] The preflight check reports the same result as it does in Shelltool
      today.
- [x] Neither file imports `Operations`.

## Tests

- [x] New `Tests/FoundationModelsMultitoolTests/SandboxPreflightTests.swift`,
      ported from
      `../FoundationModelsShelltool/Tests/ShellToolTests/SandboxPreflightTests.swift`.
- [x] New `Tests/FoundationModelsMultitoolTests/SandboxSurfaceTests.swift`,
      ported from
      `../FoundationModelsShelltool/Tests/ShellToolTests/SandboxSurfaceTests.swift`
      and `SandboxPublicSurfaceTests.swift`.
- [x] `swift test --filter Sandbox` passes.
- [x] `swift test` passes with no new failure and no new warning.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #phase-2 #eventplan