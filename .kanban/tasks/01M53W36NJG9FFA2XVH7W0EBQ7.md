---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m54pg1f4xbp5433vc63xgp9k
  text: |-
    Research (2026-10-17), the cases of the nvxckvr list checked against the current code:
    - TestSupport.makeTemporaryDirectory(named:) and makeCanonicalTemporaryDirectory(named:): about 165 calls in 33 files. The folders are never removed (the doc comment says that the operating system reclaims them). Many calls are in static helpers (makeRoot, makeDirectory, makeContext), thus a closure helper or a stored TestScratch cannot reach them without a rewrite of each test body. OPEN.
    - StubRouterFixtures: the default folder multitool-stub-ULID of makeStubSession, makeStubProfile, makeStubRun, withStubRun and withStubSession is never removed. No caller gives the in: argument. About 20000 such folders are in TMPDIR now. OPEN.
    - Other ad hoc temp paths: BackgroundSettleGraceTests (multitool-settle store folder, multitool-await log file that the snippet removes only on success), ShellCommandGateTests (2 multitool-gate-call store folders), BackgroundToolGraceCoverageTests (multitool-grace store folder). OPEN.
    - Already fixed: TestScratch suites (removal in deinit, on each path), TemporaryGitRepository (deinit), ShellCommandGate FIFO (deinit unlink), ShellStateTests fallback stores (defer).
    - Other fixtures (sessions, file handles, pipes, child processes, servers, Task values): a read-only audit found no case that closes only on success. Groups 2, 4 and 5 covered them. No `defer { Task` is in Tests/.
    Plan: one shared owner. TestScratch gets a task-local current value and explicit removeAll(). A new suite trait ownsTemporaryDirectories binds one TestScratch for each test and removes its paths in a defer, on each path. makeTemporaryDirectory(named:) registers each folder with the current TestScratch, and records an issue when no scope holds the test. The stub fixtures and the ad hoc paths use makeTemporaryDirectory(named:).
  timestamp: 2026-10-17T10:28:36.452937+00:00
- actor: claude-code
  id: 01m54pzj002t4n6t9bbtajcb0c
  text: |-
    Implementation (in the tree, not committed):
    - One shared owner. TestScratch (Fixtures/ShellStoreFixtures.swift) now has a task-local `current`, `own(_:)`, `removeAll()` and `uniqueTemporaryPath(prefix:)`. It takes the ownership before the folder exists.
    - New suite trait ownsTemporaryDirectories (Support/TemporaryDirectoryScope.swift, a TestScoping trait, recursive). It binds one TestScratch for each test case and removes its paths in a defer, thus on the return path and on the throw path. The removal is synchronous.
    - TestSupport.makeTemporaryDirectory(named:) registers each folder with TestScratch.current. A call with no trait records an issue, thus a suite that misses the trait fails. The full run had 0 such issues.
    - StubRouterFixtures: the 5 default folders (multitool-stub) now come from makeTemporaryDirectory(named: stubRouterDirectoryPrefix).
    - BackgroundSettleGraceTests (multitool-settle store, multitool-await log file), ShellCommandGateTests (2 stores), BackgroundToolGraceCoverageTests (1 store) use makeTemporaryDirectory too.
    - 60 suites have the trait: 56 added by 4 sub-agents (one attribute line each), 4 by hand.
    - New TemporaryDirectoryScopeTests: a folder made in the scope is removed when the body returns, and when the body throws. RED: the build failed (no TemporaryDirectoryScope). GREEN: 2 tests passed.
    - The checks of each test are the same. No production code changed. No IntegrationTests file changed.
    Counts: fixed 174 cases (166 makeTemporaryDirectory calls in 40 files, 5 stub router defaults, 3 ad hoc store folders, BackgroundSettleGrace log file as 1, ShellCommandGate 2 counted in the 3 stores; see list above). Already fixed: 15 TestScratch suites, TemporaryGitRepository (deinit), ShellCommandGate FIFO (deinit), 3 ShellStateTests fallback stores (defer), and all sessions, file handles, pipes, child processes and servers (audit found 0 that close only on success).
    Test: swift test, one full run, exit code 0, "Test run with 2452 tests in 211+2=213 suites passed after 5.098 seconds". The only warning is the toolchain line "missing creator for mutated node" for mlx-swift_Cmlx.bundle.
  timestamp: 2026-10-17T10:37:04.896689+00:00
- actor: claude-code
  id: 01m54q089mt9fxazf5ne4ajnf7
  text: |-
    ### implement — changed
    - correction of the counts in the comment above: cases fixed 176 = 166 makeTemporaryDirectory calls (40 files) + 5 stub router default folders + 5 ad hoc temp paths (multitool-settle store, multitool-await log file, 2 multitool-gate-call stores, multitool-grace store).
    - cases already fixed: 20 temp-path cases (15 TestScratch suites, TemporaryGitRepository deinit, ShellCommandGate FIFO deinit, 3 ShellStateTests fallback defers), and every other fixture kind (sessions, file handles, pipes, child processes, servers): 0 open.
    - shared helper: the suite trait ownsTemporaryDirectories (Tests/FoundationModelsMultitoolTests/Support/TemporaryDirectoryScope.swift) over TestScratch (Fixtures/ShellStoreFixtures.swift); TestSupport.makeTemporaryDirectory(named:) registers with it.
    - files: TestSupport.swift, Fixtures/ShellStoreFixtures.swift, Fixtures/StubRouterFixtures.swift, new Support/TemporaryDirectoryScope.swift, new TemporaryDirectoryScopeTests.swift, BackgroundSettleGraceTests.swift, ShellCommandGateTests.swift, BackgroundToolGraceCoverageTests.swift, and the trait line in 56 more suites.
    - evidence: swift test, one full run, exit code 0, "Test run with 2452 tests in 213 suites passed after 5.098 seconds"; 0 "no owner" issues; only the toolchain warning for mlx-swift_Cmlx.bundle.
    - note: ARCHITECTURE.md is not changed (test support only).
    - next: review. The task stays in doing.
  timestamp: 2026-10-17T10:37:27.732038+00:00
- actor: claude-code
  id: 01m54q34v5b5f3pmzxrfh3msj3
  text: |-
    ### test — green
    - evidence: swift test, exit code 0. Swift Testing: 2452 tests in 213 suites passed. 0 issues recorded. 0 issues say a suite has no temporary-directory owner.
    - note: the build log has one tool line, "missing creator for mutated node" for the mlx-swift_Cmlx bundle. It comes from the build tool, not from package source.
    - next: review.
  timestamp: 2026-10-17T10:39:02.501951+00:00
depends_on:
- 01M53W3412PXE4RG6PPSF7H4GS
position_column: doing
position_ordinal: '8180'
title: 'T1 group 6: temp folders and other test fixture leaks'
---
Split from ^nvxckvr (test rule T1). The list (temp folders, files and other fixtures that are removed only on the success path) is in the comments of ^nvxckvr.

Rule T1: fixtures close also when the test body throws.

Do: remove each temp folder and close each other fixture on both paths (defer for synchronous removal; an awaited helper for async close). Use one shared temp-folder helper if the same code repeats. Keep the checks of each test the same.

No .timeLimit, sleep, poll or retry. Do not delete a test. Do not change production code only to add a test hook. One full run. #elicitation-fixes #t1