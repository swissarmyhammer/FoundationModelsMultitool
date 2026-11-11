---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m75cx5hfftpf8c16v6hnjtc2
  text: |-
    Research done.
    - The verbs are internal types (Blame, Show, Log, Commit, Status, Branches, Changes, Diff). Each takes a GitContext. GitCapability(root:) holds the one context as `context` (internal). The probe reads it with `@testable import FoundationModelsMultitool` (each debug build enables testability, as MultitoolTestSupport does).
    - Files: Glob and Grep take FileContext(root:). An unscoped `**/*.txt` is a broad pattern; give `path` to permit it.
    - Snapshots: SnapshotStore(directory:), open(sessionKey:owner:workingDirectory:), take(...), then ListSnapshots(context: SnapshotsContext(store:)) under HookSession.$current.withValue.
    - The probe can not use TestSupport.makeTemporaryDirectory (test target only). It makes its own folders.
    - Package.swift says a test target can not depend on an executable; `swift test` builds each target. The probe follows the mcp-test-server pattern: an executable target plus an executable product, and the test finds it with TestServerLocator (generalized to a name).
    - Subprocess gives `Environment.custom([...])` for an exact environment.
  timestamp: 2026-11-11T13:31:38.927127+00:00
- actor: claude-code
  id: 01m75dbjs4bekfy77nc8hw7rvt
  text: |-
    Implementation landed.
    - Correction to the research comment: the probe is an executable target only, not a product. SwiftPM builds it for `swift test`, and the test finds it with `TestServerLocator.executableURL(named:)` (new; `executableURL()` calls it).
    - Discovery: `MultitoolTestSupport` linked Testing.framework through `RunOutput.swift` (`import Testing` for `Issue.record`). An executable that links the product stops at launch in dyld ("Library not loaded: @rpath/Testing.framework"). Fix: `RunOutput.decoded` now throws `RunOutputDecodingError`, whose description names the type and the raw output. Each caller uses `try`, thus the failure still names the output. New RunOutputTests (2 tests) covers it.
    - A snapshot `take` after `open` with no change gives no checkpoint. The probe writes one file after the open.
    - Proof that the test is meaningful: with the FileWalker from before 15f48d13 put back for a short time, the probe gave `FAIL files.glob` and `FAIL files.grep` (the plain walk listed build/ignored.txt), exit 1. The current FileWalker was then put back (cmp equal).
    - `env -i PATH= DEVELOPER_DIR=/nonexistent /usr/bin/git --version` gives "xcrun: error: missing DEVELOPER_DIR path: /nonexistent", exit 1. `env -i PATH= DEVELOPER_DIR=/nonexistent /usr/bin/env git --version` gives "env: git: No such file or directory", exit 127. The probe has no git call.
  timestamp: 2026-11-11T13:39:31.236250+00:00
- actor: claude-code
  id: 01m75dbnwws0wwez1t0hrnyccw
  text: |-
    ### implement — changed
    - evidence: Package.swift; Tests/Support/GitNoProgramProbe/main.swift (new); Tests/FoundationModelsMultitoolTests/GitNoProgramTests.swift (new); Tests/FoundationModelsMultitoolTests/RunOutputTests.swift (new); Tests/FoundationModelsMultitoolTests/Support/TestServerLocator.swift; Tests/Support/MultitoolTestSupport/RunOutput.swift. `swift test`: 2881 tests in 257 suites passed, exit 0. One build-system warning: "missing creator for mutated node" for .build/out/Products/Debug/mlx-swift_Cmlx.bundle (a dependency bundle, not a source file of this change). env -i check: /usr/bin/git exit 1, /usr/bin/env git exit 127.
    - next: /review
  timestamp: 2026-11-11T13:39:34.428292+00:00
- actor: claude-code
  id: 01m75dgkx1w3150fk63gq1r8w2
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (e3fa1a6c); 21 findings, 21 confirmed, 0 refuted; all code-hygiene/dead-code-swift in Tests/Support/GitNoProgramProbe/main.swift:17, 37, 87, 90, 94, 99, 102, 105, 109, 112, 117, 121, 126, 150, 162, 171, 226, 250, 262, 293, 310
    - next: implement the 21 open items in the "Review Findings (2026-11-11 07:40)" section. The task stays in review.
  timestamp: 2026-11-11T13:42:16.225869+00:00
- actor: claude-code
  id: 01m75dpnq1vfespes8ypakagq4
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (fd810b01): 0 findings, 0 confirmed, 0 refuted. Each of the 21 symbols of "Review Findings (2026-11-11 07:40)" is reached from `GitNoProgramProbeMain.main()` through `NoProgramProbe.run()` in Tests/Support/GitNoProgramProbe/GitNoProgramProbe.swift. All 21 items are checked. Five tool rules declined the old path Tests/Support/GitNoProgramProbe/main.swift because the rename removed it. These are not findings.
    - next: none. The task is in done.
  timestamp: 2026-11-11T13:45:34.689272+00:00
depends_on:
- 01M75B8B21R92BKCSGQJK087E3
position_column: done
position_ordinal: fffffff980
title: 'Test: each git verb and the file listing run with no git program'
---
## What
Request of the user (through testudoapp-75): one test that runs each git verb with no git program on PATH.

Audit result (2026-11-11): the verbs of `GitCapability` are blame, show, log, commit, status, branches, changes, diff. Each uses the `LibGit2` layer only. Snapshots use `ShadowRepository` of FoundationModelsHooks (libgit2; no child process in Hooks). The only spawns in Multitool are ShellRunner (`/bin/sh -c`), StdioServerProcess, and FileWalker (fixed by card 01M75B8B21R92BKCSGQJK087E3).

A test in the test process cannot change PATH: the suites run in parallel. Thus:
- Add an executable test target `GitNoProgramProbe` (declared in Package.swift the same way as `MCPTestServer`, at Tests/Support/GitNoProgramProbe/main.swift). It makes a temporary repository with libgit2 (two commits, a branch, a staged change, an untracked file), runs each git verb through `GitCapability(root:)` (blame, show, log, commit, status, branches, changes, diff) and the files glob and grep (FileWalker) and a snapshot list, and exits 0 only when each call gives a result with no correction.
- New test Tests/FoundationModelsMultitoolTests/GitNoProgramTests.swift starts the probe with the environment `PATH=` (empty) and `DEVELOPER_DIR=/nonexistent`, thus `/usr/bin/env git` finds nothing and the `/usr/bin/git` shim fails. The test expects exit status 0, and gives the output of the probe on a failure.

## Acceptance Criteria
- [x] The probe runs each of the 8 git verbs, the glob, the grep, and a snapshot list.
- [x] The test passes with an empty PATH and a bad DEVELOPER_DIR.
- [x] Before the FileWalker fix, the glob of the probe fails (or gives the plain walk, which the probe detects with an ignored file).

## Tests
- [x] Tests/FoundationModelsMultitoolTests/GitNoProgramTests.swift
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #step1

## Review Findings (2026-11-11 07:40)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 6 file(s) reviewed, 2 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

- [x] `Tests/Support/GitNoProgramProbe/main.swift:17` `code-hygiene/dead-code-swift` — struct `ProbeCheck` is unused.
- [x] `Tests/Support/GitNoProgramProbe/main.swift:37` `code-hygiene/dead-code-swift` — enum `ProbeRepository` is unused.
- [x] `Tests/Support/GitNoProgramProbe/main.swift:87` `code-hygiene/dead-code-swift` — var.static `passStatus` is unused.
- [x] `Tests/Support/GitNoProgramProbe/main.swift:90` `code-hygiene/dead-code-swift` — var.static `failStatus` is unused.
- [x] `Tests/Support/GitNoProgramProbe/main.swift:94` `code-hygiene/dead-code-swift` — var.static `visibleTextFiles` is unused.
- [x] `Tests/Support/GitNoProgramProbe/main.swift:99` `code-hygiene/dead-code-swift` — var.static `textFilePattern` is unused.
- [x] `Tests/Support/GitNoProgramProbe/main.swift:102` `code-hygiene/dead-code-swift` — var.static `filesWithMatchesMode` is unused.
- [x] `Tests/Support/GitNoProgramProbe/main.swift:105` `code-hygiene/dead-code-swift` — var.static `snapshotSessionKey` is unused.
- [x] `Tests/Support/GitNoProgramProbe/main.swift:109` `code-hygiene/dead-code-swift` — var.static `snapshotOwner` is unused.
- [x] `Tests/Support/GitNoProgramProbe/main.swift:112` `code-hygiene/dead-code-swift` — var.static `snapshotLabel` is unused.
- [x] `Tests/Support/GitNoProgramProbe/main.swift:117` `code-hygiene/dead-code-swift` — var.static `snapshotFile` is unused.
- [x] `Tests/Support/GitNoProgramProbe/main.swift:121` `code-hygiene/dead-code-swift` — var.static `temporaryFolderPrefix` is unused.
- [x] `Tests/Support/GitNoProgramProbe/main.swift:126` `code-hygiene/dead-code-swift` — function.method.static `run()` is unused.
- [x] `Tests/Support/GitNoProgramProbe/main.swift:150` `code-hygiene/dead-code-swift` — function.method.static `check(_:_:)` is unused.
- [x] `Tests/Support/GitNoProgramProbe/main.swift:162` `code-hygiene/dead-code-swift` — function.method.static `failure(ofCorrection:)` is unused.
- [x] `Tests/Support/GitNoProgramProbe/main.swift:171` `code-hygiene/dead-code-swift` — function.method.static `gitChecks(in:)` is unused.
- [x] `Tests/Support/GitNoProgramProbe/main.swift:226` `code-hygiene/dead-code-swift` — function.method.static `fileChecks(in:)` is unused.
- [x] `Tests/Support/GitNoProgramProbe/main.swift:250` `code-hygiene/dead-code-swift` — function.method.static `failure(ofListing:)` is unused.
- [x] `Tests/Support/GitNoProgramProbe/main.swift:262` `code-hygiene/dead-code-swift` — function.method.static `snapshotCheck(in:)` is unused.
- [x] `Tests/Support/GitNoProgramProbe/main.swift:293` `code-hygiene/dead-code-swift` — function.method.static `openStore(in:over:)` is unused.
- [x] `Tests/Support/GitNoProgramProbe/main.swift:310` `code-hygiene/dead-code-swift` — function.method.static `write(_:)` is unused.