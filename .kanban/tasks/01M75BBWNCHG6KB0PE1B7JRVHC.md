---
assignees:
- claude-code
depends_on:
- 01M75B8B21R92BKCSGQJK087E3
position_column: todo
position_ordinal: '80'
title: 'Test: each git verb and the file listing run with no git program'
---
## What
Request of the user (through testudoapp-75): one test that runs each git verb with no git program on PATH.

Audit result (2026-11-11): the verbs of `GitCapability` are blame, show, log, commit, status, branches, changes, diff. Each uses the `LibGit2` layer only. Snapshots use `ShadowRepository` of FoundationModelsHooks (libgit2; no child process in Hooks). The only spawns in Multitool are ShellRunner (`/bin/sh -c`), StdioServerProcess, and FileWalker (fixed by card 01M75B8B21R92BKCSGQJK087E3).

A test in the test process cannot change PATH: the suites run in parallel. Thus:
- Add an executable test target `GitNoProgramProbe` (declared in Package.swift the same way as `MCPTestServer`, at Tests/Support/GitNoProgramProbe/main.swift). It makes a temporary repository with libgit2 (two commits, a branch, a staged change, an untracked file), runs each git verb through `GitCapability(root:)` (blame, show, log, commit, status, branches, changes, diff) and the files glob and grep (FileWalker) and a snapshot list, and exits 0 only when each call gives a result with no correction.
- New test Tests/FoundationModelsMultitoolTests/GitNoProgramTests.swift starts the probe with the environment `PATH=` (empty) and `DEVELOPER_DIR=/nonexistent`, thus `/usr/bin/env git` finds nothing and the `/usr/bin/git` shim fails. The test expects exit status 0, and gives the output of the probe on a failure.

## Acceptance Criteria
- [ ] The probe runs each of the 8 git verbs, the glob, the grep, and a snapshot list.
- [ ] The test passes with an empty PATH and a bad DEVELOPER_DIR.
- [ ] Before the FileWalker fix, the glob of the probe fails (or gives the plain walk, which the probe detects with an ignored file).

## Tests
- [ ] Tests/FoundationModelsMultitoolTests/GitNoProgramTests.swift
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #step1