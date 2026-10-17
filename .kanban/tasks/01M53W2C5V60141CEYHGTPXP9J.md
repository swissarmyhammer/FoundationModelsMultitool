---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m53w42xdnb7f9gad4hzayxpw
  text: 'Correction to the description: "or a before the wait" means "or a `#require` check before the wait". The board read the word as a tag, and the untag removed it from the text.'
  timestamp: 2026-10-17T02:47:41.741920+00:00
- actor: claude-code
  id: 01m54rmz8sev55nr06fmw1cqrg
  text: |-
    Picked up. Research (2026-10-17), each case of item 4 of the ^nvxckvr list checked against the current code:
    - ShellBackgroundRunner: (a) the store folder from LiveRouterFixture.makeTempDir() has no owner; (b) on the throw path of the answer, the watcher task is cancelled and not awaited; (c) the wait for the stored lines of the model run has no second event when the command of the model neither writes nor ends (the end of the run comes only from the cancel after the wait). The probe can see the command in CommandSandbox.wrap (ShellState.startCommand comes before wrap, in the same task), thus a check before the wait is possible with a test-only hook in the probe; (d) the call site of ProcessExitWait.waitUntilGone has no second event (exception line); (e) firstShellRunContext already races the answer end; (f) the swept run call ends at the settle period of the product.
    - ScenarioRunner: streamAnswer ends at the terminal event of the mail (answered or answerFailed). SessionOutputLog waits already end on the stream finish and on cancel (fixed earlier). The canary run mail wait ends on the run timeout of the product. Each runner closes the session on both paths. No change.
    - LiveRouterFixture turnstile acquire: ends on cancel (ConcurrencyGate, group 1), and each holder releases on each path (resolve releases on a throw; withLiveRouterFixture tears down after the body on each path). No change.
    - ProcessExitWait (IntegrationTests copy): cancel handler and exception line from group 1. No change.
    - Temp folders with no owner: LiveRouterFixture.makeTempDir() at ShellBareSessionTests, FilesBareSessionTests, OverBudgetSurfaceDiscoveryTests, NoDescriptionSurfaceDiscoveryTests, ShellBackgroundRunner, FilesAndShellSurface (4 suites), StubRouterProfile (RouterDiscoverySeamsTests). TemporaryDirectoryScope and TestScratch stand in the unit test target, which this package cannot import.
    - MCP servers with no disconnect: MCPBareSessionTests, MCPElicitationBareSessionTests, OverBudgetSurfaceDiscoveryTests and NoDescriptionSurfaceDiscoveryTests (makeLargeCatalogSurface in the MCPTestServer product does not return its MCPServer values; the unit test OverBudgetSelectionOrderTests collects them through makeServer).
    - LiveSearchSpacing: a real-clock spacing of live requests; it always ends and a cancel ends it. It waits for no event, thus T1 does not apply. No change.
    - Also found: IntegrationNestedGenerationTool nested.respond waits for the refusal of the product (the event under test). No second event: exception line.
    - GitScenarioTests: TemporaryGitRepository removes its folder in deinit, and the test keeps it to the end. Already correct.
    - No test body in IntegrationTests/Tests has a guard with a return.
  timestamp: 2026-10-17T11:06:15.193821+00:00
- actor: claude-code
  id: 01m54s515b4ps6yeje9aerppzm
  text: |-
    Implementation (in the tree, not committed):
    - Temp folders: new IntegrationTests Support/TemporaryDirectoryScope.swift (ScratchFolders and the ownsTemporaryDirectories trait). It is a small copy of the unit-target TemporaryDirectoryScope and TestScratch: those stand in the unit test target, which this package cannot import, and no shared test-support product holds a folder scope (to move them changes each unit file that uses them). LiveRouterFixture.makeTempDir() now gives the folder to the scope of the test before it makes it, and records an issue when no trait holds the test. The trait is on the 10 suites that reach makeTempDir: ShellBareSessionTests, FilesBareSessionTests, ShellBackgroundTests, OverBudgetSurfaceDiscoveryTests, NoDescriptionSurfaceDiscoveryTests, AgentSurfaceDiscoveryTests, OperationToolLiveTests, UnknownToolHintLiveTests, RetrievalTextSurfaceDiscoveryTests, RouterDiscoverySeamsTests.
    - MCP servers: new Tests/Support/MCPTestServer/DisconnectScope.swift (disconnecting(_:after:), awaited on both paths) and LargeCatalogSurface.withMounted(...) in the shared MCPTestServer product (it records each server that the mount makes, and disconnects them when the mount throws and after the body on both paths). OverBudgetSelectionOrderTests now calls withMounted in place of its own copy of the same scaffold. MCPBareSessionTests and MCPElicitationBareSessionTests run the require check and the scenario inside DisconnectScope.disconnecting; OverBudgetSurfaceDiscoveryTests and NoDescriptionSurfaceDiscoveryTests use withMounted.
    - ShellBackgroundRunner: on the throw path of the answer, the watcher is cancelled and awaited. The wait for the stored lines now has a check before it: ShellRunContextProbe keeps the context and the command line in wrap (after ShellState.startCommand, before the spawn, same task; the default preflight now applies), and the watcher reads the live output only when the command is the scenario command, which writes a line before it waits. Note for the owner: a model run whose command differs from the quoted command now gets no live read and fails getLinesReadsLiveRun, in place of a possible wait with no end. The checks are the same.
    - Already correct (no change): firstShellRunContext, the swept run call, streamAnswer, SessionOutputLog waits, the canary run mail wait, session close on both paths in each runner, the turnstile acquire, ProcessExitWait, LiveSearchSpacing, LiveProfileReleaseTests, GitScenarioTests.
    - Exception list ^vg01093: 2 lines (ShellBackgroundRunner.swift:476 waitUntilGone call site; IntegrationNestedGenerationTool.swift:150 nested.respond).
    Counts: 13 cases fixed, 9 cases already fixed, 2 lines added to ^vg01093 (one is a case that the list of ^nvxckvr did not name).
    Build: IntegrationTests swift build --build-tests, exit 0 (only the toolchain line "missing creator for mutated node" for mlx-swift_Cmlx.bundle). Root swift test, one run, exit 0: "Test run with 2452 tests in 213 suites passed". The integration tests were not run (CI runs them).
  timestamp: 2026-10-17T11:15:01.419443+00:00
- actor: claude-code
  id: 01m54s5gaknv6sw5cmhcwqmg6a
  text: |-
    ### implement — changed
    - evidence: 21 files. New: IntegrationTests/.../Support/TemporaryDirectoryScope.swift, Tests/Support/MCPTestServer/DisconnectScope.swift. Changed: LiveRouterFixture.swift, ShellBackgroundRunner.swift, ShellRunContextProbe.swift, MCPBareSessionTests.swift, MCPElicitationBareSessionTests.swift, OverBudgetSurfaceDiscoveryTests.swift, NoDescriptionSurfaceDiscoveryTests.swift, ShellBareSessionTests.swift, FilesBareSessionTests.swift, ShellBackgroundTests.swift, AgentSurfaceDiscoveryTests.swift, OperationToolLiveTests.swift, UnknownToolHintLiveTests.swift, RetrievalTextSurfaceDiscoveryTests.swift, RouterDiscoverySeamsTests.swift, Tests/Support/MCPTestServer/LargeCatalogSurface.swift, Tests/FoundationModelsMultitoolTests/OverBudgetSelectionOrderTests.swift. Counts: 13 fixed, 9 already fixed, 2 lines on ^vg01093. IntegrationTests swift build --build-tests: exit 0. Root swift test: exit 0, 2452 tests in 213 suites passed.
    - next: test, then review. The task stays in doing.
  timestamp: 2026-10-17T11:15:16.947128+00:00
- actor: claude-code
  id: 01m54s80qdfzfqp2x31fjbz7n2
  text: |-
    ### decision — owner (2026-10-17)
    - getLinesReadsLiveRun: a model that types another command fails the scenario at once. No skip: a skip hides it.
    - The failure message must name the command that the model typed and the scenario command, so that a failure shows at once that the cause is the model choice, not the tool.
    - Push group 7 when it is done.
  timestamp: 2026-10-17T11:16:39.277840+00:00
- actor: claude-code
  id: 01m54sbhpc8watcka6rxezcwbq
  text: |-
    ### test — green
    - evidence: swift test in root package, exit 0, "Test run with 2452 tests in 213 suites passed after 5.236 seconds". No failure. No skipped test.
    - evidence: swift build --build-tests in IntegrationTests, exit 0, "Build complete". Integration tests were not run (CI runs them).
    - note: one build warning "missing creator for mutated node" for mlx-swift_Cmlx.bundle. It comes from the build system and a dependency. It does not come from this change.
    - next: review.
  timestamp: 2026-10-17T11:18:34.956302+00:00
- actor: claude-code
  id: 01m5589fp18jkbbr5z07f0c3hb
  text: |-
    Owner decision applied (getLinesReadsLiveRun message). The old failure message named neither command: "expected tools.shell.getLines to read the live run's output under the same completion token, and it read [...]". Change in IntegrationTests Support/ShellBackgroundRunner.swift only (ShellRunContextProbe.swift did not change; it already keeps the command line in `wrap`):
    - ShellRunPlaneObservation has two new fields: `scenarioCommand` (the prompt command) and `typedCommand` (the command line of the model run from the probe, set right after the execute token is known, or nil when no run came).
    - New private helper isScenarioCommand(_:expected:) does the same trimmed comparison as before. The live read gate uses it. The gate behavior is the same: the live read runs only for the scenario command.
    - New private helper liveOutputFailureMessage(for:) gives the check message: when no command was typed: "the model typed no command, thus not the scenario command `<scenario>`; the live read runs only for the scenario command". When the model typed a different command: "the model typed `<typed>`, not the scenario command `<scenario>`; the live read runs only for the scenario command". When the model typed the scenario command, the old message stays.
    - The held condition of the check (childProcessGroup != nil) did not change. No other check changed. No skip.
    Build: cd IntegrationTests and swift build --build-tests, exit 0, "Build complete!" (only the toolchain warning "missing creator for mutated node" for mlx-swift_Cmlx.bundle). The integration tests were not run (CI runs them). The root suite did not change and was not run.
  timestamp: 2026-10-17T15:39:36.001803+00:00
- actor: claude-code
  id: 01m5589hmck8fjj38eqqmxz20g
  text: |-
    ### implement — changed
    - evidence: 1 file, IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Support/ShellBackgroundRunner.swift (liveOutputFailureMessage, about line 765; observation fields scenarioCommand and typedCommand; helper isScenarioCommand). cd IntegrationTests and swift build --build-tests: exit 0.
    - next: test, then review. The task stays in doing.
  timestamp: 2026-10-17T15:39:37.996110+00:00
- actor: claude-code
  id: 01m558ak9ajd1npgv09bvdhqae
  text: |-
    ### commit — changed
    - evidence: 2c6d91f test: close temp folders and MCP servers on both paths in integration tests
    - next: review
  timestamp: 2026-10-17T15:40:12.458241+00:00
depends_on:
- 01M53W36NJG9FFA2XVH7W0EBQ7
position_column: doing
position_ordinal: '8180'
title: 'T1 group 7: the waits and fixture leaks in IntegrationTests'
---
Split from ^nvxckvr (test rule T1). The list (about 24 cases in IntegrationTests/Tests) is in the comments of ^nvxckvr.

Rule T1: each wait in a test must also end on the failure event, or the test must fail before it waits. Fixtures close also when the test body throws.

Do: fix each case with an existing second event (the call ends, the transport closes, the child process exits, the stream finishes), or a before the wait, and awaited teardown on both paths. A test-only hook in a test helper is permitted. Do not change production code only to add a test hook: bring such a case to the owner. A wait with no existing second event goes on the exception-list card, with file:line and the reason.

Build IntegrationTests with `swift build --build-tests` one time; do not run the integration tests locally (they need real dependencies); CI runs them. No .timeLimit, sleep, poll or retry. Do not delete a test. #elicitation-fixes #t1