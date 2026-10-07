---
assignees:
- claude-code
depends_on:
- 01M4C1NFFXNZ7TBRE1SJKRTE93
position_column: todo
position_ordinal: '8180'
title: 'git: add the tools.git.commit verb that shows one commit'
---
## What

This is the second half of the new read-only verb `tools.git.commit`. It is the same as the `git_show` tool of docker-agent (https://docker.github.io/docker-agent/tools/git/). The verb gives the author, the date, the full message, the parents, and the changed files with their +/- line counts for one commit. It uses `commitDetail(forRevision:)` from the dependency task (`LibGit2CommitDetail.swift`), and it never calls the C API directly (git.md § "Decisions", item 10).

At this time, the model can read only the subject of a commit (`tools.git.log`). `tools.git.show` gives the text of one file at a ref, not a commit. The verb `show` does not change.

- [ ] Make `Sources/FoundationModelsMultitool/Capabilities/Git/Commit.swift` in the pattern of `Log.swift` and `Show.swift`: `CommitArguments` (`ref: String?`, HEAD when omitted), `CommitFile` (`path`, `oldPath?`, `status`, `additions?`, `deletions?`), and `CommitResult` (`sha`, `shortSha`, `author`, `date` in ISO 8601 UTC through `LibGit2Commit.formattedDate`, `message`, `parents`, `files`, `isCapped`, `correction?`). Keep each failure in band as a `correction`: an unknown ref, a root in no repository, and a failed read. Cap the files list, and set `isCapped` when the cap cuts it. The tool description must say that the verb only reads, and it must name no path outside the git noun (see `GitCapabilityTests` "names no tool path outside the git noun").
- [ ] Keep only the files below the session root, the same as `tools.git.status`, and give each path relative to the root (`GitRepositoryLocation.rootRelativePath(fromRepositoryPath:)`).
- [ ] Add `Commit(context: context)` to `tools` in `Sources/FoundationModelsMultitool/Capabilities/Git/GitCapability.swift`, and add `commit` to the list of verbs in the file header comment.
- [ ] Add a `tools.git.commit` row to the verb table in `README.md` § "Capabilities", and change "seven verbs" to "eight verbs". Add a row to `git.md` § "Verbs".

## Acceptance Criteria

- [ ] `tools.git.commit({})` gives the HEAD commit with its full message and its changed files with counts.
- [ ] `tools.git.commit({ ref: "<sha>" })` gives that commit. A tag or `HEAD~1` also works.
- [ ] An unknown ref gives a `correction`, not a thrown error.
- [ ] A file outside the session root is not in `files`.
- [ ] `GitCapability(root:).tools.map(\.name)` holds `commit`.

## Tests

- [ ] Make `Tests/FoundationModelsMultitoolTests/GitCommitTests.swift` in the pattern of `GitLogTests.swift` and `GitShowTests.swift`. Write one test for each acceptance criterion above.
- [ ] Add `commit` to `verbNames` in `Tests/FoundationModelsMultitoolTests/GitCapabilityTests.swift`.
- [ ] Add `"tools.git.commit"` to `readmeTexts` in `Tests/FoundationModelsMultitoolTests/GitDocumentationTests.swift`.
- [ ] Run `swift test --filter Git`. All tests must pass. Then run `swift test`. The full suite must pass with no new warnings.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #git