---
assignees:
- claude-code
depends_on:
- 01M3FMSTTSP16K9AE7JKZAEFGZ
- 01M3ETW8G0BNP6JY8DNBW8B4DX
position_column: todo
position_ordinal: 8c80
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
- Use `/tdd`. Write failing tests first, then do the implementation that makes them pass. #upstream-blocked