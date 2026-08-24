---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0t6yqt3jq918rjcchvarmbz
  text: |-
    ### Research, and the blocker

    I read the card, `eventplan.md`, the three sibling verbs in
    `Capabilities/Shell/`, the upstream `ExecuteCommand.swift`, and the Router
    checkout. I wrote no source file and no test file. The tree is clean.

    **The stale sentence is corrected.** The `## What` bullet that told the handler
    to ask a policy and to send an `ask` decision through the elicitation task is
    gone. The new bullet states the decision of 2026-08-24: the shell capability
    has no permission layer, the seatbelt sandbox is the only gate, and the verb
    prompts nobody. The bullet also names the guard suite
    `ShellPermissionRemovalTests`, thus the next reader learns why the old names
    must not come back.

    **The card is blocked on the Router package.** The full evidence is now in the
    `## Blocker` section of the description. The short form:

    `SessionMailbox.park(tool:op:kind:completionToken:settling:canceler:)` is
    **internal**, and `ToolContext.mailbox` is **internal**. No public member of
    `ToolContext` or of `SessionMailbox` parks a run.
    `DetachmentParameterProviding` carries three members — `detachmentMount`,
    `detachmentClocks(from:)`, `detachmentCollectInstruction(forCompletionToken:)`
    — and none of them lets a tool declare a `RunKind` or give a canceler. The one
    `park` call in the system, at `Hosting/DetachingTool.swift` line 802, is
    hard-coded to `kind: .swiftTask` with a cooperative canceler that reports
    `.cancelled`.

    I did not stop at reading. I put a probe file in the test target that calls
    `mailbox.park(kind: RunKind.process, ...)` and I built it. The compiler said:

    ```
    error: 'park' is inaccessible due to 'internal' protection level
    ```

    Each other name resolved — `RunKind.process`, the canceler type
    `@Sendable () async -> OperationOutcome`, `context.completionToken`. The access
    level is the one obstacle. I deleted the probe and rebuilt clean.

    **Why the earlier card missed it.** The verification comment on `^wjdyxz3` of
    2026-08-24 says "Router is ready". That reading came from a `grep` for the
    member name and its parameter types. Both are correct. A `grep` cannot show an
    access level, and nobody compiled a call.

    **What a fix needs.** eventplan.md § "Processes and tasks stay different kinds"
    states the shape: "The capability gives the engine a run body plus a canceler.
    The canceler carries the capability's own semantics." Router has no such seam.
    It needs one — for example a public protocol through which a tool declares its
    `RunKind` and supplies its canceler, which `DetachingTool` reads at the park it
    already makes. Card `^wjdyxz3` forbids editing Router from this repository,
    thus that is a card for the Router board.

    **What I did not do, and why I did not do a part of it.** I did not write
    `Execute.swift` with the synchronous path alone. Five of the eight acceptance
    criteria and four of the six test items are on the detached path. A verb that
    takes a `wait` argument and then cannot detach is a different design, not a
    part of this one, and the card that follows would have to write it again.

    **Downstream:** `^1hq8xny` ("Kill shell process groups in the session-end
    sweep") needs the same seam. `^xgnygf8` and `^zpdk266` wait behind this card.
  timestamp: 2026-08-24T15:41:49.251577+00:00
- actor: claude-code
  id: 01m0t6yznz9d5vc3jhbkajnp78
  text: |-
    ### implement — stuck

    - evidence: 1 file changed — the card description itself. The stale `## What`
      bullet about a permission question is corrected, and a `## Blocker` section
      holds the full reading. No source file and no test file changed. `git status`
      over `Sources`, `Tests`, `eventplan.md` and `Package.swift` is empty, and
      `swift build --build-tests` is clean.
    - blocker: `SessionMailbox.park(...)` is internal to the FoundationModelsRouter
      module, and `ToolContext.mailbox` is internal too. Proved with the compiler:
      `error: 'park' is inaccessible due to 'internal' protection level`. Thus no
      code in this repository can park a run with `RunKind.process` and the
      `killpg` canceler, which five of the eight acceptance criteria need.
    - next: a person must decide. The fix is a public seam in the Router package —
      a way for a tool to declare its `RunKind` and give its canceler to
      `DetachingTool`, which parks today with `kind: .swiftTask` only. That is a
      card for the Router board, because `^wjdyxz3` forbids editing Router from
      here. This card stays in `doing`.
  timestamp: 2026-08-24T15:41:57.311380+00:00
- actor: claude-code
  id: 01m0t708j8ch2rpja64dq18xvn
  text: |-
    ### finish iteration 1 — stuck

    - implement: stuck — 0 source files, 0 test files. The card description was corrected (the stale permission bullet is gone; a `## Blocker` section is added).
    - test: not run — the step never reached it.
    - commit: not run.
    - review: not run.

    **The blocker, word for word from the step:** `SessionMailbox.park(tool:op:kind:completionToken:settling:canceler:)` carries no `public` keyword. It is internal to the FoundationModelsRouter module. `ToolContext.mailbox` is internal too, thus a tool cannot reach the mailbox of its own session. The public members of `ToolContext` are `post`, `progress`, `elicit`, `parkedRuns()`, `wait` and `cancel`; none of them parks. The one `park` call in the system, in `DetachingTool.swift`, is fixed at `kind: .swiftTask` with a cooperative canceler that reports `.cancelled`, thus `ToolDetachment.wrapping(...)` can never make a `.process` run.

    **Measured, not reasoned.** A probe that calls `mailbox.park(kind: RunKind.process, ...)` was compiled. The compiler answered `error: 'park' is inaccessible due to 'internal' protection level`. Every other name resolved. The probe was deleted and the tree rebuilt clean.

    **This corrects the record on `^wjdyxz3`.** That card recorded "Router is ready" from a grep of the member name and its parameter types. Both facts are true, and both are insufficient: a grep cannot show an access level, and nobody compiled a call until now.

    **What unblocks it.** Router needs the seam eventplan.md already names — *"The capability gives the engine a run body plus a canceler"* — as a public way for a tool to declare its `RunKind` and hand over its canceler, which `DetachingTool` reads at the park it already makes. `^wjdyxz3` forbids editing Router from this repository, thus that is a card for the FoundationModelsRouter board.

    **Why no partial build.** Five of eight acceptance criteria and four of six test items live on the detached path. A verb that takes `wait` but cannot detach is a different design that the next card would have to rewrite.

    **Also waiting on the same seam:** `^1hq8xny`. Behind this card: `^xgnygf8` and `^zpdk266`, and behind those `^wcnkm9b`.
  timestamp: 2026-08-24T15:42:39.176341+00:00
- actor: claude-code
  id: 01m0thxnx6kkcxf8dfdjqg1q0b
  text: |
    ### Research — the blocker is gone, and the design is forced

    **The Router seam is here, verified.** `.build/checkouts/FoundationModelsRouter` is at
    `226ff41`, and `8260def` ("feat(hosting): let a tool declare its RunKind and supply
    its own canceler") stands under it. `DetachmentParameterProviding` now carries five
    requirements, each one defaulted:

    - `var detachmentMount: DetachConfiguration?` — default `nil`
    - `func detachmentClocks(from:) -> (waitSeconds: TimeInterval?, timeout: TimeInterval?)` — default `(nil, nil)`
    - `func detachmentCollectInstruction(forCompletionToken:) -> String` — default envelope text
    - `var detachmentRunKind: RunKind` — default `.swiftTask`
    - `func detachmentCanceler(forCompletionToken:) -> (@Sendable () async -> OperationOutcome)?` — default `nil`

    `DetachingTool` reads `detachmentRunKind` and `detachmentCanceler` at the park it
    already makes, and passes `kind: runKind`. `SessionMailbox.park` stays internal, and
    this package never names it.

    **Three facts of the Router make the design of this verb forced, not chosen.**

    1. **`Output` must be `String`.** `ToolDetachment.wrapping` gives `DetachingTool` to a
       tool whose `Output` is `String`, and `ContextBindingTool` to every other tool.
       `ContextBindingTool` never parks. So a verb that must park cannot answer a
       `@Generable` result the way `getLines` and `grepHistory` do. This is the one place
       `execute` departs from its two siblings, and the reason is the Router and not a
       preference.

    2. **The verb must declare its own mount.** `RunBinding.innerCallMount` is
       `DetachConfiguration(mode: .runToCompletion)`, and every inner `tools.*` call
       travels that path. `DetachingTool` decides to detach on `configuration.mode`, and
       `detachmentClocks` cannot move the mode. A declared `detachmentMount` **wins over
       the composition site**, so it is the only way `wait: false` can ever park. This is
       the shape eventplan.md § "The constraint boundary" names: "A capability that wants
       detach semantics declares it as a usual argument (shell's `wait`)."

    3. **The canceler is already written and already tested.**
       `ShellRunner.canceler(completionToken:)` reads the process group out of
       `ShellState.runningProcess`, writes `.killed` with `completeIfRunning`, sends
       `killpg(SIGKILL)`, and reports `.stopped`. Its own file header says it is "the
       canceler that the mailbox parks beside" the run body, and until now nothing called
       it. `Execute` is its first caller.

    **What the surrounding code gives, and what it does not.**

    - There is no `ShellCapability` and no `withShell()`. Nothing registers the shell
      verbs outside one test, which uses `MultiTool.Builder().addGroup(named: "shell", …)`.
      So there is no registration list this card must join.
    - Nothing in `Sources/` derives the `"verb noun"` journal `op`. Router's
      `ToolContext.init(stamping:)` stamps both `tool` and `op` with `tool.name`, and
      `ToolContext.post(_:)` re-stamps every event with them. So the `"execute shell"`
      string is the registration site's work, not this file's, and this verb cannot set it.
    - `CommandSandbox.preflight(workingDirectory:temporaryDirectory:)` names this verb as
      its caller: the confinement must be examined before the run, so a failure reaches
      the model as readable text instead of an erased throw at spawn time.
    - `ShellState` answers no output tail. The tail comes from `record.lineCount` and
      `getLines(commandID:start:end:)`.

    **Test ground.** swift-testing, `@Suite`/`@Test`/`#expect`/`try #require`.
    `RecordingEventSink` (an actor with `events` and `details(ofKind:)`) and
    `makeOuterRunContext(mailbox:sink:)` stand in `Fixtures/RunBindingFixtures.swift`.
    `TestScratch` stands in `Fixtures/ShellStoreFixtures.swift`, and each shell suite
    roots a `ShellState` in a temporary directory and never calls the bare `init()`.
    Each run mints its token with `SessionMailbox.makeCompletionToken()`.

    **The guard suite.** `ShellPermissionRemovalTests` fails when `ShellPolicy`,
    `ShellDecisionStore`, `ShellPolicyError` or `decisions.yaml` appears as a plain
    substring of any line of `Sources/`, of `Tests/`, of `eventplan.md` or of
    `Package.swift` — a doc comment included. This verb names none of them, and it asks
    no permission question: the seatbelt sandbox is the only gate.
  timestamp: 2026-08-24T18:53:28.870447+00:00
- actor: claude-code
  id: 01m0tjjybyyay937bt84htfcy4
  text: |
    ### The verb landed — what it does, and the one bullet it cannot carry

    Two new files, and nothing else in the tree moved:

    - `Sources/FoundationModelsMultitool/Capabilities/Shell/Execute.swift`
    - `Tests/FoundationModelsMultitoolTests/ShellExecuteTests.swift`

    **How it parks, in one line.** `Execute` conforms to
    `DetachmentParameterProviding` and declares `.process` plus the canceler
    `ShellRunner.canceler(completionToken:)` already supplies. `DetachingTool` reads
    both at the park it already makes. No code here names `SessionMailbox.park`.

    **Two design choices were forced by the Router, and both are written into the
    file rather than left for a reader to rediscover.**

    1. `Output` is `String`, where the two siblings answer a `@Generable` value.
       `ToolDetachment.wrapping` gives `DetachingTool` only to a `String`-output
       tool, and `ContextBindingTool` — which never parks — to every other one. The
       answer renders through `ResultRenderer`, so it reads as `runCode` and `wait`
       read.
    2. The verb declares a `detachmentMount` of `.detaching`. Every inner `tools.*`
       call travels `RunBinding.innerCallMount`, which is `.runToCompletion`, and
       `DetachingTool` decides to detach on the MODE alone. A clock cannot move a
       mode, so a verb that answered a zero wait clock under that mount would still
       block. A declared mount wins over the composition site, and that declaration
       is what `wait: false` rests on. The work clock is left absent, because
       `ShellRunner` already arms the `timeout` argument as a killer of the process
       group, and because it keeps the `waitSeconds >= timeout` refusal of
       `DetachConfiguration` out of reach.

    `wait` stays an ordinary argument. The verb performs no elevation of its own: it
    reports a block window of zero from `detachmentClocks(from:)`, and the engine
    does the rest.

    **Progress comes off the live view.** The verb hands `ShellRunner` a
    `ShellOutputChunkStream`, and one task drains it and posts each chunk as a
    `progress` event. A gap is reported rather than passed over, because output that
    went away must not read as output that never came. The terminal event carries
    the same rendered report the call answers with, so its `detail` holds the tail
    and the identifier, which is what eventplan.md asks a terminal event to carry.
    A mounted call's second terminal is dropped by `RunEventFunnel`, so exactly one
    reaches a session either way.

    **A call with no session runs nothing**, and says so in band. The verb mints no
    identifier, so with no ambient context there is no `commandID` for the store, no
    `correlationID` for the events, and no token for the run plane. That is the
    honest reading of "mints nothing".

    **No permission layer, and the guard suite proves it.**
    `ShellPermissionRemoval` passes over the new files: they name no `ShellPolicy`,
    no `ShellDecisionStore`, no `ShellPolicyError` and no `decisions.yaml`, in code
    or in a comment. The seatbelt sandbox is the only gate, and the verb asks it —
    through `CommandSandbox.preflight`, before the run — whether it can confine the
    command at all, rendering a `SeatbeltSandboxError` as corrective text.

    ### The one bullet that is NOT in this diff

    The `## What` bullet says "the journal `op` is `"execute shell"`". **It is
    `"execute"`, and no code in this file can change that.**

    Router's `ToolContext.init(stamping:)` stamps BOTH `tool` and `op` with
    `tool.name`, and `ToolContext.post(_:)` re-stamps every event it forwards — only
    `kind`, `detail`, `outcome` and `elicitation` survive. So a verb that built an
    event carrying `op: "execute shell"` has that value overwritten. The verb also
    does not know its own noun: `register(noun:tool:)` supplies the noun and
    `Tool.name` supplies the verb, and only the registration site holds both.

    eventplan.md § "Registration of capabilities: noun/verb" assigns the work there
    in as many words: "Registration derives it as `"\(verb) \(noun)"`." That
    derivation does not exist anywhere in `Sources/` today, for any verb — this is
    not a gap this card opened.

    It is recorded as its own card rather than left silent: **`^fs7ywtg` — "Derive
    the \"verb noun\" journal op at registration"**.

    Everything else on the card — every acceptance criterion and every listed
    test — is in the diff and green.
  timestamp: 2026-08-24T19:05:05.662867+00:00
- actor: claude-code
  id: 01m0tjm64weq5xy110cjz3p1pa
  text: |
    ### implement — changed

    - evidence: 2 files, both new —
      `Sources/FoundationModelsMultitool/Capabilities/Shell/Execute.swift` and
      `Tests/FoundationModelsMultitoolTests/ShellExecuteTests.swift`. `git status`
      over `Sources`, `Tests`, `eventplan.md` and `Package.swift` shows those two
      and nothing else. `swift test --filter ShellExecute`: 10 tests, 1 suite,
      passed. `swift test`: 572 tests in 47 suites, passed.
      `swift build --build-tests`: no compiler warning.
      `ShellPermissionRemoval` passes over the new files.
    - 8 of 8 acceptance criteria and 8 of 8 test items are checked and green.
    - gap, named rather than skipped: the journal `op` is `"execute"` and not
      `"execute shell"`. Router stamps `op` from `tool.name` and re-stamps every
      posted event, and a verb does not know its own noun, so no code in this file
      can set it. eventplan.md assigns the derivation to the registration site,
      where it does not exist for any verb yet. Tracked as `^fs7ywtg`.
    - next: `/review`. The card stays in `doing`.
  timestamp: 2026-08-24T19:05:46.396771+00:00
- actor: claude-code
  id: 01m0tm9fp9qcy6m2t4t4hk1ebp
  text: |-
    ### test — green
    - evidence: `swift test` — 572 tests, 47 suites, 0 failed, 0 skipped. Ran the full suite 10 times after the fix below; all 10 clean. One pre-existing build-system warning present on every run: `missing creator for mutated node` for `mlx-swift_Cmlx.bundle` — names a resource bundle of the pinned `mlx-swift` dependency, not code owned by this package (confirmed by stashing the two new files and reproducing it unrelated to this task; also documented on prior test comments for this repo). Out of scope.
    - A real race was found and fixed while checking the detached-run tests for stray processes, per instruction. Two of the first `swift test` runs (before the fix) leaked orphaned `sleep 30` processes (reparented to pid 1): `ShellExecuteTests`' `wait: false` tests cancel a run immediately after it parks, and the block window for `wait: false` is zero (`Execute.detachmentClocks(from:)`), so the cancel could reach `ShellRunner.canceler(completionToken:)` before the spawn closure had called `ShellState.registerProcess(commandID:pid:)`. The old canceler read `ShellState.runningProcess(commandID:)`, found no pid, sent no `killpg`, and still reported `.stopped` — the process then spawned moments later with nobody left to stop it.
    - Fix: `ShellState.pidToCancel(commandID:)` now suspends (via `CheckedContinuation`) instead of returning `nil` when no pid is registered yet. `registerProcess(commandID:pid:)` resumes it with the pid the moment the child registers; `completeCommand(commandID:status:exitCode:)` resumes it with `nil` on every exit path that ends the command with no pid ever registered (a spawn that throws, above all), so a waiter is never left suspended forever. `ShellRunner.canceler(completionToken:)` now awaits `pidToCancel` first, sends `killpg` if a pid comes back, and only then writes `.killed` — so the canceler never returns until the process is dead or certainly never existed. Verified the fix in isolation with a temporary 200-iteration direct race test (`ShellRunner.canceler` vs `ShellRunner.run`, no Router involved) before and after: leaked processes before, zero after; removed the temporary test afterward.
    - Files changed: `Sources/FoundationModelsMultitool/Capabilities/Shell/ShellState.swift`, `Sources/FoundationModelsMultitool/Capabilities/Shell/ShellRunner.swift`. `Sources/FoundationModelsMultitool/Capabilities/Shell/Execute.swift` and `Tests/FoundationModelsMultitoolTests/ShellExecuteTests.swift` (this card's own files) were not modified.
    - Also ran `ShellRunnerTests`, `ShellStateTests`, `ShellExecuteTests` in isolation (69 tests, 3 suites) — all green, including `cancelerStopsALongCommandAndReportsStopped`, `cancelerKillsTheWholeProcessGroupAndNotTheLeaderAlone`, and `completeIfRunningLeavesAnAlreadyStoppedCommandUntouched`, which cover the ordering this fix touches.
    - next: none. The suite is clean and no stray process remains after any run.
  timestamp: 2026-08-24T19:34:52.873408+00:00
depends_on:
- 01M0NAK9M8RG58Q7BTTWJDYXZ3
position_column: doing
position_ordinal: '80'
title: Add the tools.shell.execute verb
---
## What

eventplan.md § "Registration of capabilities: noun/verb" fixes the layout: one
folder for each noun, and one file for each verb. The file holds the
`@Generable` Arguments, the Output, the handler that reads
`ToolContext.current`, the doc comment, and one example snippet.

- Create
  `Sources/FoundationModelsMultitool/Capabilities/Shell/Execute.swift`.
- `struct Execute: Tool` with `name = "execute"`. The path is
  `tools.shell.execute`, and the journal `op` is `"execute shell"`.
- Arguments come from
  `../FoundationModelsShelltool/Sources/ShellTool/Operations/ExecuteCommand.swift`:
  the command, the working directory, the environment, the timeout, and the
  `wait` detach flag.
- eventplan.md § "The constraint boundary": *"A capability that wants detach
  semantics declares it as a usual argument (shell's `wait`). The capability
  then returns the run's identifier for the builtins."* Keep `wait` as an
  ordinary argument. The verb itself never elevates.
- The handler:
  - Reads `ToolContext.current` one time, at operation start. It captures the
    context into the object that continues after the call. eventplan.md §
    "The ambient context" makes this rule mandatory.
  - Mints nothing. It uses the run's `completionToken` from the context as the
    `commandID`.
  - **Asks no permission question, and prompts nobody.** By the decision of
    2026-08-24 (eventplan.md § "Consolidation of the siblings") the shell
    capability has no permission layer at all. The seatbelt sandbox is the
    only gate on a command. There is no allow, no reject, and no question.
    An earlier version of this bullet named a policy type and an elicitation
    path. That design was deleted, and the guard suite
    `Tests/FoundationModelsMultitoolTests/ShellPermissionRemovalTests.swift`
    fails if its names come back into `Sources/`, `Tests/`, `eventplan.md`, or
    `Package.swift`.
  - **Parks the run in the session mailbox** when the command detaches. It
    parks with `RunKind.process`, with the run's settling task, and with the
    `killpg(SIGKILL)` canceler that the `ShellRunner` task supplies. This is
    the one place that parks a shell run. The session-end sweep then reaches
    it.
  - Posts a `progress` event as output arrives, and one terminal event at the
    end.
  - Returns the output tail plus the run identifier, so that the model knows
    how to get more.
- The doc comment carries one runnable example snippet. `findAPIs` serves that
  snippet.

Out of scope: the command-length check and the environment-value check
(length, NUL, CR/LF). Those belong to card `^xgnygf8`, which depends on this
one.

## The blocker of 2026-08-24 is GONE — 2026-08-24, later

The earlier `## Blocker` section of this card said the card could not be built,
because `SessionMailbox.park` and `ToolContext.mailbox` are internal to the
FoundationModelsRouter module. **That reading was correct, and the seam it
asked for has since shipped.** The section is replaced by this one so that no
later reader acts on a blocker that no longer stands.

Router commit `8260def` ("feat(hosting): let a tool declare its RunKind and
supply its own canceler") is on `origin/main`, and
`.build/checkouts/FoundationModelsRouter` is at `226ff41`. `park` is still
internal, and it stays internal by design. The public seam is the existing
protocol `DetachmentParameterProviding`, which gained two defaulted
requirements:

- `var detachmentRunKind: RunKind` — default `.swiftTask`
- `func detachmentCanceler(forCompletionToken:) -> (@Sendable () async -> OperationOutcome)?`
  — default `nil`

`DetachingTool` reads both at the park it already makes, and passes
`kind: runKind`. So a capability declares what kind of run it starts and how to
stop one, and the engine parks it on those terms. This card names no `park`.

## Acceptance Criteria

- [x] `tools.shell.execute` renders with an `@example` line that runs as
      written.
- [x] A short command returns its output inline.
- [x] A command started with `wait: false` returns the run identifier, and the
      run continues.
- [x] A detached command is parked in the session mailbox with
      `RunKind.process` and with the `killpg` canceler.
- [x] `ToolContext.parkedRuns()` lists the detached run under its completion
      token.
- [x] The `commandID` of the run, its event `correlationID`, and its
      `completionToken` are the same string.
- [x] The handler reads `ToolContext.current` one time, at start.
- [x] Exactly one terminal event is posted for each run.

## Tests

- [x] New `Tests/FoundationModelsMultitoolTests/ShellExecuteTests.swift`,
      ported from
      `../FoundationModelsShelltool/Tests/ShellToolTests/ExecuteCommandTests.swift`.
- [x] A test asserts the three identifiers are one string.
- [x] A test with a recording sink asserts exactly one terminal event, and one
      or more `progress` events before it.
- [x] A test asserts a `wait: false` call returns the identifier and does not
      block.
- [x] A test asserts the detached run appears in `ToolContext.parkedRuns()`
      with `RunKind.process`.
- [x] A test calls `ToolContext.cancel(completionToken:)` on the detached run
      and asserts it reports `.reported(.stopped)`.
- [x] `swift test --filter ShellExecute` passes.
- [x] `swift test` passes with no new failure and no new warning.

## The one bullet that did not land, and why

The `## What` bullet states that "the journal `op` is `"execute shell"`". It is
`"execute"`, and **no code in `Execute.swift` can change that**:

- Router's `ToolContext.init(stamping:)` stamps BOTH `tool` and `op` with
  `tool.name`.
- `ToolContext.post(_:)` re-stamps every event it forwards. Only `kind`,
  `detail`, `outcome` and `elicitation` survive, so an event built carrying
  `op: "execute shell"` has that value overwritten.
- A verb does not know its own noun. `register(noun:tool:)` supplies the noun
  and `Tool.name` supplies the verb, and only the registration site holds both.

eventplan.md § "Registration of capabilities: noun/verb" assigns the work to
that site in as many words: "Registration derives it as `"\(verb) \(noun)"`."
No verb of this package journals a `"verb noun"` op today, so this is not a gap
this card opened.

It is tracked as `^fs7ywtg` — "Derive the \"verb noun\" journal op at
registration".

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #phase-2 #eventplan