---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4c5k2s07qh5w9f9a0n9mbpf
  text: |-
    Research done.
    - The verb follows Log.swift: `context.repository.resolve(corrective:)`, then `LibGit2Repository(discoveringFrom:).commitDetail(forRevision:)`. A nil detail gives `GitContext.unknownRefMessage(ref)`. A thrown error gives `PathCorrective.pathErrorMessage(description:path:)`, the same as Log.
    - Root filter: `GitRepositoryLocation.rootRelativePath(fromRepositoryPath:)`. To match `tools.git.status`: a rename from outside the root is a new file below the root (status "added", no oldPath). A rename from below the root to outside the root is a removal of the old path (status "deleted").
    - The short sha length (7) is a private constant in Log.swift. Commit needs the same value. Plan: move it to a `shortSha` property on `LibGit2Commit`, and Log reads it. Thus one constant.
    - All five `LibGit2FileStat` properties get read, thus all five periphery markers go.
    - `TestSupport.runGit` makes a tag in a test.
  timestamp: 2026-10-07T21:51:23.936416+00:00
- actor: claude-code
  id: 01m4c60k7fzbqn0w9z0qbgsh3j
  text: |-
    Implementation landed (TDD: GitCommitTests failed to compile first, because Commit/CommitArguments/CommitResult did not exist; then 11/11 passed).
    - New: Commit.swift (verb, fileCap = 200), GitCommitTests.swift (11 tests: HEAD, sha, tag + HEAD~1, file outside root, rename into / out of / inside root, cap, unknown ref, ref that names no commit (`HEAD:a.txt`), root in no repository).
    - Shared code, to keep one copy: `LibGit2Commit.shortSha` (Log used a private 7-char constant; Log now reads the shared property). `GitContext.read(at:in:failedDescription:_:)` in GitBlobReader.swift holds the unknown-ref and failed-read corrections; Log and Commit both call it. `LibGit2FileStat.addedStatus/modifiedStatus/deletedStatus/renamedStatus` replace the private status literals of LibGit2CommitDetail.swift, and Commit reads them.
    - Removed all five `// periphery:ignore` markers and reason lines on LibGit2FileStat: Commit.swift reads path, oldPath, status, additions, deletions.
    - Decision recorded: a rename across the root follows `tools.git.status`. Into the root = "added", no oldPath. Out of the root = "deleted" at the old path. The line counts stay the counts of the diff.
    - Verb order in GitCapability.tools: blame, show, log, commit, status, branches, changes, diff.
    - Note: each swift build prints `warning: missing creator for mutated node: (.../mlx-swift_Cmlx.bundle/Contents/MacOS)`. That is a SwiftPM build-graph line for a dependency bundle, not a compiler warning, and no changed file causes it.
  timestamp: 2026-10-07T21:58:46.767316+00:00
- actor: claude-code
  id: 01m4c60np2hagnkzk7gswv4c88
  text: |-
    ### implement — changed
    - evidence: 13 files (2 new: Sources/FoundationModelsMultitool/Capabilities/Git/Commit.swift, Tests/FoundationModelsMultitoolTests/GitCommitTests.swift; changed: GitBlobReader.swift, GitCapability.swift, LibGit2Commit.swift, LibGit2CommitDetail.swift, Log.swift, GitCapabilityTests.swift, GitDocumentationTests.swift, README.md, git.md). `swift test --filter GitCommitTests`: 11 passed. `swift test --filter Git`: 254 tests in 31 suites passed. `swift test`: 2268 tests in 196 suites passed, 0 failures, no compiler warnings.
    - next: /review
  timestamp: 2026-10-07T21:58:49.282839+00:00
- actor: claude-code
  id: 01m4c638se64b3fhs63vw8ty54
  text: |-
    ### test — green
    - evidence: swift test — 2268 tests in 196 suites passed, 0 failed, 0 skipped.
    - warning: one build warning, "missing creator for mutated node" from mlx-swift_Cmlx.bundle. It comes from a dependency. It is not our code.
    - note: Package.resolved keeps the local FoundationModelsRanker pin d75a67c. No package update was run.
    - next: review.
  timestamp: 2026-10-07T22:00:14.382725+00:00
depends_on:
- 01M4C1NFFXNZ7TBRE1SJKRTE93
position_column: doing
position_ordinal: '80'
title: 'git: add the tools.git.commit verb that shows one commit'
---
## What

This is the second half of the new read-only verb `tools.git.commit`. It is the same as the `git_show` tool of docker-agent (https://docker.github.io/docker-agent/tools/git/). The verb gives the author, the date, the full message, the parents, and the changed files with their +/- line counts for one commit. It uses `commitDetail(forRevision:)` from the dependency task (`LibGit2CommitDetail.swift`), and it never calls the C API directly (git.md § "Decisions", item 10).

At this time, the model can read only the subject of a commit (`tools.git.log`). `tools.git.show` gives the text of one file at a ref, not a commit. The verb `show` does not change.

- [x] Make `Sources/FoundationModelsMultitool/Capabilities/Git/Commit.swift` in the pattern of `Log.swift` and `Show.swift`: `CommitArguments` (`ref: String?`, HEAD when omitted), `CommitFile` (`path`, `oldPath?`, `status`, `additions?`, `deletions?`), and `CommitResult` (`sha`, `shortSha`, `author`, `date` in ISO 8601 UTC through `LibGit2Commit.formattedDate`, `message`, `parents`, `files`, `isCapped`, `correction?`). Keep each failure in band as a `correction`: an unknown ref, a root in no repository, and a failed read. Cap the files list, and set `isCapped` when the cap cuts it. The tool description must say that the verb only reads, and it must name no path outside the git noun (see `GitCapabilityTests` "names no tool path outside the git noun").
- [x] Keep only the files below the session root, the same as `tools.git.status`, and give each path relative to the root (`GitRepositoryLocation.rootRelativePath(fromRepositoryPath:)`).
- [x] Add `Commit(context: context)` to `tools` in `Sources/FoundationModelsMultitool/Capabilities/Git/GitCapability.swift`, and add `commit` to the list of verbs in the file header comment.
- [x] Add a `tools.git.commit` row to the verb table in `README.md` § "Capabilities", and change "seven verbs" to "eight verbs". Add a row to `git.md` § "Verbs".

## Acceptance Criteria

- [x] `tools.git.commit({})` gives the HEAD commit with its full message and its changed files with counts.
- [x] `tools.git.commit({ ref: "<sha>" })` gives that commit. A tag or `HEAD~1` also works.
- [x] An unknown ref gives a `correction`, not a thrown error.
- [x] A file outside the session root is not in `files`.
- [x] `GitCapability(root:).tools.map(\.name)` holds `commit`.

## Tests

- [x] Make `Tests/FoundationModelsMultitoolTests/GitCommitTests.swift` in the pattern of `GitLogTests.swift` and `GitShowTests.swift`. Write one test for each acceptance criterion above.
- [x] Add `commit` to `verbNames` in `Tests/FoundationModelsMultitoolTests/GitCapabilityTests.swift`.
- [x] Add `"tools.git.commit"` to `readmeTexts` in `Tests/FoundationModelsMultitoolTests/GitDocumentationTests.swift`.
- [x] Run `swift test --filter Git`. All tests must pass. Then run `swift test`. The full suite must pass with no new warnings.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #git