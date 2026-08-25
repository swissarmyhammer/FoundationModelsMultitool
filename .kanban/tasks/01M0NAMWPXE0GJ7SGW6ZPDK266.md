---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0tvebxq2q4vmxxffrn5d3c3
  text: |-
    ### Research

    **The card was stale on the policy parameter.** By the decision of 2026-08-24 the
    shell has no permission layer. `ShellPolicy`, `ShellPolicyError`,
    `ShellDecisionStore` and `decisions.yaml` are deleted, and
    `ShellPermissionRemovalTests` fails if any of those four names comes back in
    `Sources/`, `Tests/`, `eventplan.md` or `Package.swift`. The `## What` bullet is
    corrected: the initializer takes the store directory, the sandbox and the output
    chunk stream, and no policy.

    **The real signatures the capability composes.**

    - `Execute` has exactly one initializer, `init(runner: ShellRunner)`. It reaches
      the store, the sandbox and the output chunk stream only through the runner.
    - `GetLines.init(state: ShellState)` and `GrepHistory.init(state: ShellState)`.
    - `ShellRunner` is a struct with `let state: ShellState` and the `var` members
      `maxOutputSize`, `registry`, `outputChunkStream` and `sandbox`.
    - `ShellState.init(preferredDirectory: URL?) throws` and `ShellState() throws`.
      Both THROW, so `ShellCapability.init` throws and `Builder.withShell()` throws
      with it. That is resource acquisition, not validation, so it does not break
      the rule that no registration method raises `MultiToolBuilderError`.
    - `ShellOutputChunkStream` and `CommandSandbox` are both `public`, so a `public
      ShellCapability` exposes no lower-access type.

    **`findAPIs` ships as `searchTools` / `SearchToolsTool`** (plan.md § "Names that
    moved"). A test drives it with `SearchToolsTool(searcher:limit:)` over a
    `MetadataSearcher`, and the formatted answer carries each entry's verbatim
    `block` plus `Example: <entry.qualifiedExample>`.

    **`help()` and `docs(name)`** are host functions inside the sandbox, built from
    `registry.surface.entries` alone: `help()` answers the paths, `docs(name)`
    answers that entry's `block`. A test drives them through
    `MultiTool(registry:).call(arguments: RunCodeArguments(code: "return help();"))`.

    **The `"execute shell"` journal op cannot be reached from this package.**
    Router's `ToolContext.init(stamping:)` is the one stamping site, and it writes
    the wrapped tool's own `name` into BOTH `tool` and `op`:

        let stamp = tool.name.isEmpty ? String(describing: type(of: tool)) : tool.name
        self.init(..., tool: stamp, op: stamp, ...)

    Its own doc comment states the gap: *"phase 1 stamps the wrapped tool's `name`
    here too, until noun/verb registration supplies the canonical `"verb noun"`
    string."* `OperationDefinition` / `opString`, which `OperationEvent.op` names,
    does not exist in either package. So a shell run's op is `"execute"` today, and
    `"execute shell"` needs the noun to travel from `Capability.noun` into the
    `ToolContext` Router mints — a change in the dependency, which Router card
    ^8y20bwd carries. ^fs7ywtg is stuck on the same wall.

    **Discovery, not asked for by this card.** `Execute.report(of:in:)` builds a
    FRESH `ShellOutputChunkStream` for each run and assigns it over
    `running.outputChunkStream`, so a stream a host supplies to the capability never
    receives a chunk. The card asks for the parameter, so it is wired; the gap is
    recorded as its own task rather than repaired here.
  timestamp: 2026-08-24T21:39:52.887864+00:00
- actor: claude-code
  id: 01m0tvx4vmjjq7dan6wjdr3xk7
  text: |-
    ### Implementation landed

    `ShellCapability` is a `public struct` holding `noun = "shell"` and the three
    verbs, built in one throwing initializer over one `ShellState`:

        public init(
            storeDirectory: URL? = nil,
            sandbox: (any CommandSandbox)? = nil,
            outputChunkStream: ShellOutputChunkStream? = nil
        ) throws

    One store reaches the run-plane verb through `ShellRunner` and reaches the two
    content-plane verbs directly, so the three answer for the same session. A test
    holds that with `===` on the actor.

    `MultiTool.Builder.withShell(storeDirectory:sandbox:outputChunkStream:)` builds
    that capability and hands it to `withCapability(_:)`. It is the one registration
    method that throws, and it never throws a `MultiToolBuilderError`; the header
    doc of that type now says so, because its old sentence — "the fluent chain needs
    `try` only on the final call" — was no longer the whole truth.

    **`MultiTool.description` gets NO new sentence.** The card asked for one "only if
    the shell capability needs it", and it does not: the three verbs are ordinary
    `tools.shell.*` entries that `searchTools`, `help()` and `docs()` all render,
    which is exactly what the globals sentence exists to say is NOT true of the
    ambient globals. Three tests hold that — `searchTools` finds each verb with its
    runnable example, `help()` names all three paths, and `docs(name)` hands back
    each verb's own block.

    **The one card item that did not land: the `"execute shell"` journal op test.**
    It cannot pass from this package, for the reason in the research comment above:
    Router's `ToolContext.init(stamping:)` writes the wrapped tool's `name` into
    `op`, so the op of a shell run is `"execute"`. No edit inside
    `FoundationModelsMultitool` can change that — the noun must travel into the
    `ToolContext` Router mints. Router card ^8y20bwd carries the fix. No test was
    written for it, because a test that asserted `"execute shell"` today would be a
    failing test rather than a proof, and one that asserted `"execute"` would lock
    in the state this card wants moved.

    Discovered along the way and filed as its own card, ^7kydt76: a
    `ShellOutputChunkStream` handed to the capability never receives a chunk,
    because `Execute.report(of:in:)` replaces `runner.outputChunkStream` with a
    private stream for each run. The parameter is wired as the card asked; the repair
    belongs to that card.

    ### implement — stuck
    - evidence: 3 files — `Sources/FoundationModelsMultitool/Capabilities/Shell/ShellCapability.swift` (new), `Sources/FoundationModelsMultitool/Surface/MultiToolBuilder.swift` (`withShell` plus the corrected `MultiToolBuilderError` header), `Tests/FoundationModelsMultitoolTests/ShellCapabilityTests.swift` (new, 9 tests). `swift test --filter ShellCapability`: 9 passed. `swift test`: 586 tests in 47 suites passed, 0 failures, 0 new warnings, over five consecutive runs. `swift test --filter ShellPermissionRemoval`: 4 passed.
    - gap: the `"execute shell"` journal op test. Blocked on Router `ToolContext.init(stamping:)`; Router card ^8y20bwd carries the fix, ^fs7ywtg is stuck on the same wall.
    - next: a human decides whether ^zpdk266 waits on ^8y20bwd or goes to review with that one test item deferred to it.
  timestamp: 2026-08-24T21:47:57.172083+00:00
- actor: claude-code
  id: 01m0tw24bmkshnzhrth88kpnmw
  text: |-
    ### finish iteration 1 — stuck

    12 of the 13 items landed and the tree is green. The one gap is external and already tracked.

    - implement: stuck — 3 files. Capabilities/Shell/ShellCapability.swift (new): `public struct ShellCapability: Capability`, noun `"shell"`, the three verbs over one shared `ShellState`, one throwing initializer taking the store directory, the sandbox and the output chunk stream. NO policy parameter — the card was stale there, and that sentence is corrected. Surface/MultiToolBuilder.swift: `withShell(...)`, the one registration method that throws, plus a corrected `MultiToolBuilderError` header. Tests/ShellCapabilityTests.swift (new, 9 tests).
    - test: green — swift test, 586 passed in 47 suites, 0 failed, 0 new warnings, over five consecutive runs. `--filter ShellPermissionRemoval` passes, thus no deleted policy name came back.
    - commit: 3c0ec31 feat(shell): add ShellCapability and Builder.withShell()
    - review: not run.

    **The gap.** The `"execute shell"` journal op test did not land and cannot land from this package. Router's `ToolContext.init(stamping:)` is the one stamping site and writes the wrapped tool's own `name` into both `tool` and `op`. Its own doc comment states the gap: *"phase 1 stamps the wrapped tool's `name` here too, until noun/verb registration supplies the canonical `\"verb noun\"` string."*

    The implementer wrote no test for it, and the reasoning is right: one asserting `"execute shell"` would be a failing test rather than a proof, and one asserting `"execute"` would lock in the state the card wants moved.

    Router card `^8y20bwd` — "Let a registration site give a tool its journal op" — carries the fix. `^fs7ywtg` is stuck on the same wall.

    **The decision a person owns:** hold this card until `^8y20bwd` lands, or send it to `/review` with that one test item moved onto `^8y20bwd`. The card is NOT forced to done either way.

    **New work found:** `^7kydt76` — a `ShellOutputChunkStream` handed to the capability never receives a chunk, because `Execute.report(of:in:)` replaces `runner.outputChunkStream` with a private stream for each run. The parameter is wired as this card asked; the repair belongs to that card.
  timestamp: 2026-08-24T21:50:40.500379+00:00
- actor: claude-code
  id: 01m0wj9s99fjp1m8a78zp77ec6
  text: |
    ### The last item landed: the `"execute shell"` journal op test

    **The block is gone.** Router f31f453 carries the seam
    `ToolContext.init(stamping:op:)`, where the stamp is `op: declared ?? stamp`.
    Multitool ^fs7ywtg (commit 14de9ce) carries the consumer side: the registration
    site derives the `"verb noun"` string and hands it down through
    `ToolInvoker.invoke(_:content:binding:journalOp:)` and
    `RunBinding.invoke(_:arguments:journalOp:)` into
    `ToolDetachment.wrapping(..., op:)`. So the mechanism already gives
    `"execute shell"`, and this step is the test alone. No code changed.

    **Where the test stands, and why there.**
    `Tests/FoundationModelsMultitoolTests/RegisteredJournalOpTests.swift`, beside
    the other six journal-op tests. That file already holds the helpers this test
    needs (`makeShellRegistry(in:)`, `run(_:over:under:)`, `makeOuterRunContext`),
    thus the test adds no second copy of them. Its suite header names the two
    readings a registered run makes observable, and the new test is the second one
    made on the SHELL: *"the `op` a called verb reads out of its own
    `ToolContext.current`"*.

    **What it reads, and why the other readings do not answer.**

    - The rendered `APISurface.Entry.journalOp` is a declaration, not a run.
    - `ParkedRun.op` answers only for a run that PARKS, which the existing detached
      test covers. An awaited `execute` call settles inside the call, thus it
      stands on no plane a test can read afterwards.
    - The event journal of the snippet answers the OUTER op: `ToolContext.post(_:)`
      re-stamps every event it forwards. Router's own doc comment says a test that
      looked for the declared op there asserts the wrong plane.

    So the test reads the run's own `ToolContext`. `Execute` asks its sandbox to
    `preflight` from INSIDE the call, before it spawns, thus a probe
    `CommandSandbox` reports `ToolContext.current?.op` for that run. The probe
    gives the shell invocation back unchanged, thus the command really starts and
    the verb keeps its production shape.

    **The red step, on behaviour that already worked.** The test cannot fail for a
    missing feature, so the proof that it is not vacuous is a mutation: the first
    run asserted the pre-seam value `"execute"`. It failed with
    `stampedOp → "execute shell"`, which shows the probe reads the live stamp and
    that the `#require` on "the run consulted its sandbox" holds. The expectation
    then moved to the pair, and it passed.

    **Discovery.** The probe sandbox is the only seam inside a real `execute` run
    that a test can stand on. Nothing else the verb touches is injectable AND runs
    under the run's own ambient context.
  timestamp: 2026-08-25T13:38:34.409690+00:00
- actor: claude-code
  id: 01m0wjebawqt40gjqeyac8wq8d
  text: |
    ### implement — changed
    - evidence: 1 file — `Tests/FoundationModelsMultitoolTests/RegisteredJournalOpTests.swift`. It adds the test `anAwaitedShellRunCarriesThePair`, the probe fixture `JournalOpProbeSandbox`, the `inlineCommand` constant, and a `sandbox:` parameter with a default on the private helper `makeShellRegistry(in:sandbox:)`, thus no second copy of the store setup. NO production file changed: the mechanism of ^fs7ywtg and Router f31f453 already gives `"execute shell"`.
    - red: the first run asserted the pre-seam `"execute"` and failed with `stampedOp → "execute shell"`, thus the probe reads the live stamp and the test can fail. The expectation then moved to the pair.
    - green: `swift test --filter RegisteredJournalOp`: 7 tests passed. `swift test --filter ShellCapability`: 10 tests in 2 suites passed. `swift test`: 595 tests in 48 suites passed, 0 failures, over four runs. The count was 594 before, thus exactly one test was added. The one warning is the pre-existing SwiftPM `missing creator for mutated node` from the vendored mlx-swift, which is out of scope.
    - card: the last unchecked item of the description is now `[x]`, and its BLOCKED note is replaced by where the test stands. All 13 items are checked.
    - next: `/review`. The card stays in `doing`.
  timestamp: 2026-08-25T13:41:03.964887+00:00
- actor: claude-code
  id: 01m0wjqp99amcmad0h281b4rg8
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit 72a21f4) — 0 findings, 0 confirmed, 1 refuted, 7 attempted, 0 failed. 1 source file reviewed (Tests/FoundationModelsMultitoolTests/RegisteredJournalOpTests.swift); 4 `.kanban/` files excluded by `.reviewignore`. No prior `## Review Findings` section on the card; all 13 checklist items are checked.
    - next: card moved to `done`.
  timestamp: 2026-08-25T13:46:10.089470+00:00
- actor: claude-code
  id: 01m0wjrczyx37jbpafypdyzmr5
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 1 file, `Tests/FoundationModelsMultitoolTests/RegisteredJournalOpTests.swift`. The card's last item, the `"execute shell"` journal-op test, was blocked on Router ^8y20bwd and its consumer ^fs7ywtg. Both landed, so the item was written and checked off. No production file changed: the mechanism already produced the right op once the registration-site derivation landed.
    - The test is `anAwaitedShellRunCarriesThePair`, with a private `JournalOpProbeSandbox`. It reads `ToolContext.current?.op` from inside `Execute`'s own call, which is the one field both `ParkedRun.op` and `ToolInvocationRecord.op` are built from, and passes the invocation through unchanged so the command really runs. The other readings cannot answer for an awaited run: the surface entry is a declaration and not a run, `ParkedRun.op` answers only for a run that parks, and the snippet journal answers the OUTER op because `ToolContext.post(_:)` re-stamps forwarded events.
    - test: green — swift test 595 tests in 48 suites passed, 0 failures. That is up exactly one from 594. `--filter ShellCapability` 10 passed; `--filter RegisteredJournalOp` 7 passed. The implementer ran the full suite green four times, so no separate test step was run.
    - commit: 72a21f4 — test(shell): assert an execute run carries the op "execute shell" (^zpdk266)
    - review: clean — `review sha HEAD~1..HEAD`, 0 findings, 1 candidate refuted, 7 validator pairs attempted; card landed in done

    All 13 of 13 checklist items are now checked.
  timestamp: 2026-08-25T13:46:33.342215+00:00
depends_on:
- 01M0NAKY7B8H1Z0J2VCBWV86SY
- 01M0NAMBSX4GXQ1ETQXZ6ZWRN5
position_column: done
position_ordinal: f380
title: Add ShellCapability and Builder.withShell()
---
## What

eventplan.md § "The capability contract": the modules are opt-in, and they are
off by default. eventplan.md § "Registration of capabilities: noun/verb":
*"`withShell()` is a short form of `withCapability(ShellCapability(...))`."*

- Create
  `Sources/FoundationModelsMultitool/Capabilities/Shell/ShellCapability.swift`.
  - `public struct ShellCapability: Capability`.
  - `noun` is `"shell"`.
  - `tools` is exactly `[Execute(...), GetLines(...), GrepHistory(...)]`.
  - The initializer takes the store directory, the sandbox, and the output
    chunk stream. Each has a default. **There is no policy parameter.** By the
    decision of 2026-08-24 the shell has no permission layer: `ShellPolicy` is
    deleted, and `ShellPermissionRemovalTests` fails if that name comes back
    anywhere in `Sources/` or `Tests/`.
- Add `public func withShell(...) -> Self` to
  `Sources/FoundationModelsMultitool/Surface/MultiToolBuilder.swift`. It calls
  `withCapability(ShellCapability(...))`.
- Shell is off by default. A `MultiTool` that is built with no `withShell()`
  has no `tools.shell` namespace at all.
- Do not add `listProcesses` and do not add `killProcess`. eventplan.md §
  "Consolidation of the siblings" removes them. `status()` and
  `cancel(completionToken)` replace them.
- Add one sentence to `MultiTool.description` only if the shell capability
  needs it. The globals sentence is already there.

## Acceptance Criteria

- [x] `ShellCapability.noun` is `"shell"`, and `tools` holds exactly three
      tools.
- [x] `Builder().withShell().buildRegistry()` renders exactly
      `shell.execute`, `shell.getLines`, and `shell.grepHistory`.
- [x] A builder with no `withShell()` renders no entry whose path starts with
      `shell.`.
- [x] The surface has no `listProcesses` entry and no `killProcess` entry.
- [x] `findAPIs` finds the three shell entries, each with its sample snippet.
- [x] `help()` and `docs()` render the three entries.

## Tests

- [x] New `Tests/FoundationModelsMultitoolTests/ShellCapabilityTests.swift`.
- [x] A test asserts the three rendered paths, and asserts the set has exactly
      three members.
- [x] A test asserts a builder with no `withShell()` renders no `shell.` entry.
- [x] A test asserts `findAPIs` returns each shell entry with a runnable sample
      snippet.
- [x] A test asserts the journal `op` of an execute run is `"execute shell"`.
      **The block is gone.** Router f31f453 carries the seam
      `ToolContext.init(stamping:op:)`, and ^fs7ywtg (commit 14de9ce) carries
      the registration site that derives the pair. The test is
      `anAwaitedShellRunCarriesThePair` in
      `Tests/FoundationModelsMultitoolTests/RegisteredJournalOpTests.swift`,
      where the other journal-op tests stand. It runs an awaited
      `tools.shell.execute` through `withShell()` and reads the run's own
      stamp. No code changed: the mechanism already gives `"execute shell"`.
- [x] `swift test --filter ShellCapability` passes.
- [x] `swift test` passes with no new failure and no new warning.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #phase-2 #eventplan