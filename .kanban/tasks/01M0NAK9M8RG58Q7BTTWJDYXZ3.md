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

Note: `SessionMailbox.park(kind:)` needs `RunKind.process`, which Router does
not have yet. `RunPlane.swift` names it as the phase 2 seam. A card is filed on
the FoundationModelsRouter board. Do not edit the Router package from this
repository.

## Acceptance Criteria

- [ ] `ShellRunner` is in
      `Sources/FoundationModelsMultitool/Capabilities/Shell/`, and it has no
      `wait:` parameter and no deadline race.
- [ ] `RunSupervisor` does not exist in this repository.
- [ ] `ProcessRegistry` holds the child process groups, and it keeps the
      `atexit` backstop. It has no race logic.
- [ ] The canceler sends `killpg(SIGKILL)` and returns
      `OperationOutcome.stopped`.
- [ ] The run body records into `ShellState` and `OutputBuffer` under the
      completion token.
- [ ] No file in `Capabilities/Shell/` imports `Operations`.

## Tests

- [ ] New `Tests/FoundationModelsMultitoolTests/ShellRunnerTests.swift`, ported
      from
      `../FoundationModelsShelltool/Tests/ShellToolTests/ShellRunnerTests.swift`,
      with every deadline-race test removed.
- [ ] New `Tests/FoundationModelsMultitoolTests/ShellProcessRegistryTests.swift`,
      ported from `ProcessRegistryTests.swift`.
- [ ] A test starts a long command (`sleep 30`), runs the canceler, and asserts
      the returned outcome is `.stopped` and the child process is gone.
- [ ] A test asserts the child's whole process group dies, not the leader
      alone.
- [ ] `swift test --filter ShellRunner` and `swift test --filter ShellProcessRegistry`
      pass.
- [ ] `swift test` passes with no new failure and no new warning.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #phase-2 #eventplan