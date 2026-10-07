---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4bjx3516w7vnc2kzmwe567x
  text: 'Research: of the seven git verbs, only the `Show` description names a path outside the git mount (`tools.files.read`). No `@Guide` text of a git verb names such a path. The other `tools.files.read` texts in the git folder are `//` and `///` source comments, which the model does not read. No golden in `Tests/**/Goldens` holds a git description. `APISurface.Entry.block` holds the rendered description, the argument guides (`@param`), and the example of one entry; the new test reads it for each entry of `MultiTool.Builder().withGit(root:)`. The test goes in `GitCapabilityTests.swift`.'
  timestamp: 2026-10-07T16:24:49.057360+00:00
- actor: claude-code
  id: 01m4bkbfjnh9vd7mcpwredb4qn
  text: 'Implementation landed. RED: the new test `eachGitVerbNamesNoToolPathOutsideTheGitNoun` failed with only `git.show` -> ["tools.files.read"]; the other six verbs were clean. GREEN: the `Show` description now says "Omit ref to read the file at HEAD. To compare it with the work folder, use tools.git.diff: a path with no ref reads the work folder." Note: a `static let` of a regex literal does not compile under Swift 6, because `Regex` is not `Sendable`; the pattern is a local in the helper, as in `UnknownToolHint.swift`. Full suite: 2267 tests in 196 suites pass. Live `GitScenarioTests`: 1 test passes; turn 27.9 s, 2 tool calls (searchTools, runCode), typed only git.diff; test 36.9 s. The one build warning ("missing creator for mutated node" on the mlx-swift_Cmlx bundle) comes from the build system for a dependency, not from this change.'
  timestamp: 2026-10-07T16:32:40.533905+00:00
- actor: claude-code
  id: 01m4bkbhp54smxxghfafzgr3gx
  text: |-
    ### implement — changed
    - evidence: 2 files — Sources/FoundationModelsMultitool/Capabilities/Git/Show.swift, Tests/FoundationModelsMultitoolTests/GitCapabilityTests.swift; swift test 2267 tests / 196 suites passed; GitScenarioTests 1/1 passed (turn 27.9 s, 2 tool calls, test 36.9 s)
    - next: review
  timestamp: 2026-10-07T16:32:42.693729+00:00
- actor: claude-code
  id: 01m4bkkm29h6wh7csbt0333d2r
  text: |-
    ### test — green
    - evidence: swift build --build-tests: complete, 0 errors. swift test: 2267 tests in 196 suites passed, 0 failed, 0 skipped. IntegrationTests swift build --build-tests: complete, 0 errors.
    - warnings: only the known dependency warning "missing creator for mutated node" for mlx-swift_Cmlx.bundle. It was there before. It is not counted as red.
    - next: review
  timestamp: 2026-10-07T16:37:07.273336+00:00
- actor: claude-code
  id: 01m4bkm86nvvaqa76nfsh5sfrw
  text: |-
    ### commit — changed
    - evidence: one local commit "fix(git): do not name tools.files.read in the git.show description" with Show.swift, GitCapabilityTests.swift, and all .kanban changes (includes leftover files of ^m3em6nf). The sha is in the final step record of the caller. No push.
    - next: review
  timestamp: 2026-10-07T16:37:27.893554+00:00
- actor: claude-code
  id: 01m4bkyaxgw01agvec2y2rgxna
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit c3e4848). findings 0, confirmed 0, refuted 0, attempted 7, failed 0. 2 files reviewed: Sources/FoundationModelsMultitool/Capabilities/Git/Show.swift, Tests/FoundationModelsMultitoolTests/GitCapabilityTests.swift. 4 .kanban files not reviewed (.reviewignore). The commit renames no file.
    - next: none. The task is in done.
  timestamp: 2026-10-07T16:42:58.352791+00:00
- actor: claude-code
  id: 01m4bkyvk9erm2gvq6vpra7whp
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 2 files (Show.swift description, GitCapabilityTests.swift new test); git live scenario 27.9 s, 2 tool calls
    - test: green — swift test, 2267 passed in 196 suites; IntegrationTests build complete
    - commit: c3e4848
    - review: clean — 0 findings, 7 validator runs
  timestamp: 2026-10-07T16:43:15.433704+00:00
position_column: done
position_ordinal: ffffc180
title: 'git: the git.show description names tools.files.read, also when no files capability is mounted'
---
## Problem

The description of `tools.git.show` says: "Omit ref to read the file at HEAD; tools.files.read reads the file in the work folder instead." A host can mount git alone (`MultiTool.Builder().withGit(root:)`). Then `tools.files.read` does not exist.

## Evidence

Local integration run, 2026-10-07 (task ^k6wzrxn): with the prompt "compare Sources/Geometry.swift at HEAD with the file in the work folder", the model searched for a file reader four times, then called `tools.files.read` (the snippet failed: "tools.files.read does not exist"), and called `git.diff` only after 8 tool calls. The turn took 171 s instead of approximately 27 s.

## Work

- Make the description of `git.show` name only verbs that the mount has, or name `git.diff` (a path with no ref reads the work folder) for the work-folder side.
- Add a unit test that the description of each git verb names no tool path outside the git mount when git is mounted alone. #git