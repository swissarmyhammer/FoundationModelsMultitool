---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3fpgdr3frkc34emh8hk6zpa
  text: |-
    Answer from the router session (2026-09-26) about the three types without a named home:
    - `SessionEvent`: the library uses it only in doc comments (`Capabilities/Files/FileChangeJournal.swift:24` and `:59`). The value in that event is `ToolCallReport`, which moves to Extras in task 01M3FP9700G1GWA15B0GEZQGMD. Change the comments so that they refer to the tool call report and do not name the Router event.
    - `RunKind`: now in Router's `Hosting/RunPlane.swift`. It moves to Extras in task 01M3FP9700G1GWA15B0GEZQGMD.
    - `OperationEvent`: already in Extras (Router has only a typealias). Import it from `FoundationModelsExtras`.
    So no Router card is necessary for these three.
  timestamp: 2026-09-26T20:29:04.131068+00:00
- actor: claude-code
  id: 01m3gcnbmzjwdvmycztvnq4wx8
  text: |-
    Facts from the router session (2026-09-26) for the Extras tool-hosting API:
    - The Extras work is done locally, but it is NOT pushed (the user approves pushes). The commit to pin is Extras `11404f3`. Do not start this task until Extras `main` on origin contains `11404f3`, and Router 01M3FPCADD0GTFAV2RANXKE7G0 is pushed.
    - Router's `SessionMailbox` is `RunPlane` in Extras. Its public API: `init`, `makeCompletionToken`, `attach(settlementObserver:)`, `backgroundRuns`, `settledRunTokens`, `respond`, `complete`, `sweep`, `wait(completionToken:seconds:)`.
    - Tests: our tests call the internal `track`, `updateProgress`, `wait` and `sweep` through `@testable`. `wait` and `sweep` are public now. There is no `track(... settling:)`. Use `start(tool:op:kind:completionToken:canceler:body:)`: the body returns the terminal `OperationEvent`, and a `nil` canceler cancels the body task. `start`, `RunPlane.StartResult` and `updateProgress(completionToken:detail:)` are `@_spi(Testing) public`. `@testable` does not give access to SPI, so a test file that uses them needs `@_spi(Testing) @testable import FoundationModelsExtras`.
    - `PendingRunEnvelope.decoded(fromRendered:)` is now `makeDecoded(fromRendered:)`.
  timestamp: 2026-09-27T02:56:14.495479+00:00
- actor: claude-code
  id: 01m3mgwb4g4vhht6qja6rwp94y
  text: |-
    Implementation notes (iteration 1):
    - Every hosting type has a public home in FoundationModelsExtras (4a733cd): ToolContext, BackgroundTool, ToolMount, ToolMounting, SubmissionBoundaryTool, LostRunError, RunKind, BackgroundRun, ToolCallReport, OperationEvent, RunPlane, ElicitationRequestedSchema. The library needs no Router symbol. SessionEvent and RoutedSession occur in no library file now.
    - Router re-exported ULID before. The library now links the ULID product (yaslab/ULID.swift, from 1.3.1) itself, for `ElicitationRequest.elicitationId`.
    - `MessageID` has an internal init in Extras. CLIAnswerDrainTests and ScenarioGradingTests now use `@testable import FoundationModelsExtras`.
    - ScenarioGrading and the unit test target keep Router: they use `TranscriptEvent` and `SubmissionID`, which stay in Router.
    - New test suite: PackageManifestTests (library target has no Router product, MultitoolCLI has it, no library source imports Router).
  timestamp: 2026-09-28T17:26:55.376697+00:00
- actor: claude-code
  id: 01m3mh6yfbdn94g5em2wgqyjw3
  text: |-
    ### test — green
    - evidence: `swift build --build-tests` clean. `swift test`: 1820 tests in 146 suites passed, 0 failed, 0 skipped. `swift build --package-path IntegrationTests --build-tests`: Build complete. The only warnings are the known mlx bundle "missing creator" line, SwiftPM manifest-cache "disk I/O error" lines, and C++17 warnings in the third-party mlx-swift Metal kernels. None comes from this code.
    - note: the first run failed in `applicationTargetDeclaresRouter`: the dependency line `.target(name: packageName),` split the MultitoolCLI declaration. Correction: a declaration starts only at a line that is exactly `.target(`, `.executableTarget(` or `.testTarget(`.
    - next: commit
  timestamp: 2026-09-28T17:32:42.859117+00:00
- actor: claude-code
  id: 01m3mh7cjscknryta2kmxxwtcf
  text: |-
    ### commit — changed
    - evidence: 5a90600 refactor(package): take tool hosting from FoundationModelsExtras
    - next: review HEAD~1..HEAD
  timestamp: 2026-09-28T17:32:57.305833+00:00
- actor: claude-code
  id: 01m3mhen7f1mt6jvb52xfypazd
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD — 0 findings, 0 confirmed, 0 refuted; 32 files reviewed (README.md, plan.md: no validator matches; .kanban: ignored)
    - next: done

    ### finish iteration 1 — clean
    - implement: changed — Package.swift, README.md, plan.md, 29 library sources, 3 test files (PackageManifestTests new)
    - test: green — swift test 1820 tests in 146 suites passed; IntegrationTests --build-tests complete
    - commit: changed — 5a90600 refactor(package): take tool hosting from FoundationModelsExtras
    - review: clean — 0 findings on HEAD~1..HEAD
  timestamp: 2026-09-28T17:36:55.535928+00:00
depends_on:
- 01M3FMSTTSP16K9AE7JKZAEFGZ
- 01M3ETW8G0BNP6JY8DNBW8B4DX
position_column: done
position_ordinal: fff680
title: Take tool hosting from FoundationModelsExtras, and remove the FoundationModelsRouter dependency from the library target
---
## What
User decision (2026-09-26, from the router session): FoundationModelsExtras owns all tool hosting (the interface and the implementation, moved from Router's `Hosting/` folder), a process-wide `ModelPool`, one FIFO work queue for each pooled model, and a `Mailbox`. Router is one user of Extras. The Multitool library must use Extras and the metadata registry, and it must not depend on Router. Router stays only in `MultitoolCLI`, which is the application.

**Upstream blockers (other boards, so they cannot be `depends_on` here). Do not start this task until each one is done and pushed:**
- Extras 01M3FPA83C04HNESZYBEBTPRDG: makes the tool-hosting API public. The tool-hosting chain is 01M3FP9700G1GWA15B0GEZQGMD, 01M3FP9FGARYJFK9NYQMRY5QM0 and 01M3FP9WTFQEQZ8Q4YJDXRA4D9.
- Router 01M3FPCADD0GTFAV2RANXKE7G0: removes Router's `Hosting/`.

Name change: Router's `SessionMailbox` is `RunPlane` in Extras. So `SessionMailbox.makeCompletionToken()` and `ToolContext.makeCompletionToken()` become `RunPlane.makeCompletionToken()`.

- [ ] In `Package.swift`, remove `.product(name: routerDependencyName, ...)` from the library target (`packageName`), from `scenarioGradingTargetName` if it needs no Router symbol, and from the unit test target where it is possible. Keep it on `cliLibraryTargetName`. Update the manifest comments.
- [ ] In `Sources/FoundationModelsMultitool/`, change each `import FoundationModelsRouter` (19 files on 2026-09-26) to `import FoundationModelsExtras` for the hosting types: `ToolContext` (72 uses), `BackgroundTool`, `ToolMount`, `SubmissionBoundaryTool`, `LostRunError`, `RunPlane.makeCompletionToken()`. Also check that `OperationEvent` (18 uses), `RunKind` and `SessionEvent` / `RoutedSession` have a home in Extras or the registry. If a symbol has no home, stop, and write the card text for the correct board.
- [ ] Move each remaining Router-only use in the library (for example a `RoutedSession` doc reference, or `MultiTool+Forking.swift`) to `MultitoolCLI`, or remove it.
- [ ] Update plan.md and README.md to say that tool hosting comes from FoundationModelsExtras, and that the library does not depend on Router.

## Acceptance Criteria
- [ ] `rg -l 'import FoundationModelsRouter' Sources/FoundationModelsMultitool` returns no file.
- [ ] The library target in `Package.swift` does not list the FoundationModelsRouter product.
- [ ] `swift build --build-tests`, `swift test` and `swift build --package-path IntegrationTests --build-tests` pass.

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/DependencyReachTests.swift` (or `PackageManifestTests.swift`): read `Package.swift` and assert that the `FoundationModelsMultitool` target has no FoundationModelsRouter dependency, and that `MultitoolCLI` has one.
- [ ] A test that no file under `Sources/FoundationModelsMultitool` imports `FoundationModelsRouter`.
- [ ] Run `swift build --build-tests && swift test`. Expected result: all tests pass.

## Workflow
- Use `/tdd`. Write failing tests first, then do the implementation that makes them pass.