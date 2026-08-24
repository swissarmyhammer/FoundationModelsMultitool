---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0r6883f9hztdrhfqqphgjpz
  text: |-
    ### Research

    Read the source, the target and the rules.

    **Router is ready.** `RunKind.process` exists in the checkout at
    `.build/checkouts/FoundationModelsRouter/.../Hosting/RunPlane.swift`. The note in
    `## What` that says Router does not have it is out of date. `SessionMailbox.park`
    takes `canceler: @escaping @Sendable () async -> OperationOutcome`, which is the
    signature the card states.

    **The store already carries the seam.** `Capabilities/Shell/ShellState.swift` was
    ported before this card and it holds:
    - `startCommand(_:commandID: String)` — the caller mints the token, the store
      mints nothing.
    - `registerProcess(commandID:pid:)` and `runningProcess(commandID:) -> pid_t?`.
      The doc comment of `runningProcess` says the canceler must read the process
      group from the store and must not hold a pid of its own. Thus the port needs no
      `Mutex<pid_t>` box, and `killProcessGroupOnCancel` from the sibling goes away.
    - `CommandStatus.killed`, documented as "`cancel(completionToken)` is the one path
      that reaches this status".
    - `completeIfRunning(commandID:status:exitCode:)` — the atomic transition that
      keeps a cancel from being written over.

    **`ShellState.killProcess` does not exist here.** The sibling test
    `killProcessMidStreamCapturesLinesEmittedBeforeTheKill` calls it. The canceler
    takes that role, so that test becomes the canceler test the card asks for.

    **Differences from the sibling the port must carry:**
    - The identifier is a `String` token, not an `Int`. `Request` carries it, because
      `run(_ request: Request)` is the only entry point the card keeps.
    - `ShellOutputChunkStream.send(commandID:from:bytes:maxSize:)` takes the token
      `String` and a `ShellOutputStream`, not a composed `ShellCommandID`. Thus the
      sibling's `OutputChunkRoute` structure holds nothing that is not already in
      scope, and it goes away. `StreamChunk` carries `ShellOutputStream` in place of
      `isStdout: Bool`.
    - `runBody` was `static` only because a detached `Task` ran it. With the race
      gone, the body is `run` itself and the helpers are instance methods.
    - `10 * 1024 * 1024` becomes `10_485_760` (one number).
    - No `Operations` import. `OperationOutcome` comes from `FoundationModelsRouter`.

    **Rules that bind this change** (`dump validators`, 7 validators, 55 rules): each
    numeric literal gets a name (swiftlint `no_magic_numbers`, allowed `[0, 1, -1,
    100]`, and a Swift Testing suite is NOT a test carve-out for it — the neighbouring
    `ShellStateTests` names every literal as a `private static let`); no dead symbol;
    no duplicated block; documentation on each item.
  timestamp: 2026-08-23T20:51:03.407257+00:00
- actor: claude-code
  id: 01m0t32nxtg6j59kp1vz5zfx7r
  text: |-
    ### Verification of the whole card

    The card sat in `doing` with a research comment and no step record, but the work
    already landed in the tree through later commits. I checked each acceptance
    criterion and each test item against the real code. All of them hold. I wrote no
    new code.

    **The six acceptance criteria:**

    1. `ShellRunner.swift` is in `Capabilities/Shell/`. The only entry point is
       `run(_ request: Request) async throws -> Outcome`. The header of the file
       states that the runner holds no race, no detach and no supervision. A grep of
       the file for `wait:` and `events:` finds nothing.
    2. `RunSupervisor` — zero matches in `Sources/`.
    3. `ProcessRegistry.swift` holds a `Mutex<Set<pid_t>>` table and the `atexit`
       backstop, and it holds no race logic. It is a lock and not an actor, because
       the `atexit` closure can await nothing.
    4. `canceler(completionToken:) -> @Sendable () async -> OperationOutcome` reads
       the pid with `runningProcess(commandID:)`, writes `.killed` with
       `completeIfRunning`, sends `killpg(pid, SIGKILL)`, and returns `.stopped`.
       The canceler holds no pid of its own, thus the store stays the one home of
       that pid.
    5. The run body calls `startCommand`, `registerProcess`, `appendLines` and
       `completeIfRunning`, each one under the completion token, and it drains
       through `OutputBuffer`.
    6. `import Operations` — zero matches in `Sources/`.

    **The two test cases the parent could not confirm both exist**, and neither one
    needed new work:

    - `cancelerStopsALongCommandAndReportsStopped` starts a long `sleep`, runs the
      canceler, expects `.stopped`, polls `pgrep -f` until the count is 0, and then
      expects the record status `.killed`.
    - `cancelerKillsTheWholeProcessGroupAndNotTheLeaderAlone` starts
      `sleep N & sleep N`, waits for both members, runs the canceler, and expects
      zero survivors.

    **One difference from the card text, which is safe.** The card says `sleep 30`.
    The tests sleep for a random marker of 100_000 to 999_999 seconds instead. The
    marker makes the `pgrep -f` pattern unique to one test, thus a parallel suite
    cannot count a `sleep` that it does not own. The command is longer than 30
    seconds, thus it satisfies "a long command" more strictly, not less.

    **The stale note in `## What` is now corrected.** I verified the claim of the
    research comment myself:
    - `RunKind.process` is at `Hosting/RunPlane.swift` of the Router checkout, and
      its doc comment states that the run plane holds the canceler closure and never
      calls `killpg` itself.
    - `park(tool:op:kind:completionToken:settling:canceler:)` is at
      `Hosting/SessionMailbox.swift`, and `canceler` has the type
      `@escaping @Sendable () async -> OperationOutcome`.

    Thus nothing on the Router board blocks this card. I edited no file of the Router
    package.

    **The one warning of the full run is not new and it is not ours.** It reads
    `missing creator for mutated node: (… mlx-swift_Cmlx.bundle/Contents/MacOS)`. It
    comes from the build graph of the `mlx-swift` dependency, and not from a source
    file of this package.
  timestamp: 2026-08-24T14:34:04.090289+00:00
- actor: claude-code
  id: 01m0t32ychfjmm1b0xeyhb3gnw
  text: |-
    ### implement — changed

    - evidence: 1 file changed — the card description itself. I checked the 12
      checkboxes of `## Acceptance Criteria` and `## Tests`, because each one holds
      in the tree, and I corrected the stale note in `## What` that said Router has
      no `RunKind.process`. No source file and no test file needed an edit: the two
      canceler tests the card asks for already exist
      (`cancelerStopsALongCommandAndReportsStopped`,
      `cancelerKillsTheWholeProcessGroupAndNotTheLeaderAlone`).
    - tests: `swift test --filter ShellRunner` — 27 tests, 1 suite, passed.
      `swift test --filter ShellProcessRegistry` — 4 tests, 1 suite, passed.
      `swift test` — 562 tests, 46 suites, passed. Zero failures. The one warning
      comes from the build graph of the `mlx-swift` dependency, and it is not new.
    - next: `/review`.
  timestamp: 2026-08-24T14:34:12.753359+00:00
depends_on:
- 01M0NAGFZW81T7W42D3WT1T8MC
- 01M0NAHA4F1WVK2JY5C3QHRKEY
position_column: doing
position_ordinal: '8280'
title: Port ShellRunner as a run body and a canceler, and delete the local race
---
## What

eventplan.md § "Consolidation of the siblings": *"consolidation is promotion,
not construction"*, and *"Detach supervision moves to the shared engine."*
`ShellRunner` today owns its own deadline race, its own detach, and its own
supervision. The `DetachingTool` engine in Router owns all three now.

- Create `Sources/FoundationModelsMultitool/Capabilities/Shell/ShellRunner.swift`
  from `../FoundationModelsShelltool/Sources/ShellTool/ShellRunner.swift`
  (1158 lines).
- Delete the deadline race. The port keeps only
  `run(_ request: Request) async throws -> Outcome` — the run body. It does not
  keep `run(_:wait:events:)`.
- Do not port `../FoundationModelsShelltool/Sources/ShellTool/RunSupervisor.swift`.
  The mailbox holds the parked run now.
- Create `Sources/FoundationModelsMultitool/Capabilities/Shell/ProcessRegistry.swift`
  from the Shelltool file, but keep only the child process-group table and the
  `atexit` backstop. Delete the race logic.
- Add a canceler: a `@Sendable () async -> OperationOutcome` closure that sends
  `killpg(SIGKILL)` to the run's process group and returns
  `OperationOutcome.stopped`. `killpg` is authoritative, so the outcome is
  `.stopped`, never `.cancelled`.
- The run body writes into `ShellState` and `OutputBuffer` under the run's
  completion token.

Note: `SessionMailbox.park(kind:)` needs `RunKind.process`, and Router HAS it.
The checkout holds `RunKind.process` in `Hosting/RunPlane.swift`, and
`park(tool:op:kind:completionToken:settling:canceler:)` in
`Hosting/SessionMailbox.swift`, whose `canceler` parameter has the type
`@escaping @Sendable () async -> OperationOutcome` — exactly the signature this
card names. Thus no card on the FoundationModelsRouter board blocks this one.
Do not edit the Router package from this repository.

## Acceptance Criteria

- [x] `ShellRunner` is in
      `Sources/FoundationModelsMultitool/Capabilities/Shell/`, and it has no
      `wait:` parameter and no deadline race.
- [x] `RunSupervisor` does not exist in this repository.
- [x] `ProcessRegistry` holds the child process groups, and it keeps the
      `atexit` backstop. It has no race logic.
- [x] The canceler sends `killpg(SIGKILL)` and returns
      `OperationOutcome.stopped`.
- [x] The run body records into `ShellState` and `OutputBuffer` under the
      completion token.
- [x] No file in `Capabilities/Shell/` imports `Operations`.

## Tests

- [x] New `Tests/FoundationModelsMultitoolTests/ShellRunnerTests.swift`, ported
      from
      `../FoundationModelsShelltool/Tests/ShellToolTests/ShellRunnerTests.swift`,
      with every deadline-race test removed.
- [x] New `Tests/FoundationModelsMultitoolTests/ShellProcessRegistryTests.swift`,
      ported from `ProcessRegistryTests.swift`.
- [x] A test starts a long command (`sleep 30`), runs the canceler, and asserts
      the returned outcome is `.stopped` and the child process is gone.
- [x] A test asserts the child's whole process group dies, not the leader
      alone.
- [x] `swift test --filter ShellRunner` and `swift test --filter ShellProcessRegistry`
      pass.
- [x] `swift test` passes with no new failure and no new warning.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #phase-2 #eventplan