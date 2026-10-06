---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m48ykwhr5rqa7gh6b3hrawe5
  text: |-
    Research (before code):
    - `MultiTool.Builder.withCapability(_:)` records a noun claim for a capability with zero tools too. Thus two `withGit` calls fail as `.duplicateNoun` at `buildRegistry()`, and `register(noun: "git", ...)` beside `withGit` fails the same way.
    - Reuse: `resolvedPath(_:)` (`Capabilities/Shell/SeatbeltSandbox.swift`) is the one `realpath(3)` helper of the module. `PathContainment` gives the path parts. `CorrectiveRejection` + `Result.resolve(corrective:then:)` (`Capabilities/Files/CorrectiveResult.swift`) is the in-band correction shape. The git base uses these three, so no new copy.
    - Plan: `GitContext` is a `struct` (no shared mutable state). It holds `root`, `pathGuard` (the same rules as `FileContext`), and `repository: Result<GitRepositoryLocation, CorrectiveRejection>`. The not-in-a-repository case is a failure value, not a throw.
    - `GitRepositoryLocation` holds the `realpath` work folder and the root parts below it. It changes a repository path to a root path (nil when outside the root) and back (lexical, nil when `..` goes above the work folder).
    - `LibGit2` layer: `LibGit2` (start, check, makeHandle, last error text), `LibGit2Error` (code + text, `isNotFound`), `LibGit2Repository` (owns `git_repository *`, discovery with `git_repository_open_ext`, frees in `deinit`). Typed throws `throws(LibGit2Error)`.
    - Test helper `TemporaryGitRepository` goes in `MultitoolTestSupport`, which then links `gitProducts`. It sets HEAD to `refs/heads/main` itself (spike fact 2).
  timestamp: 2026-10-06T15:51:47.000536+00:00
- actor: claude-code
  id: 01m48zbnx05zhvzj0ymkxq6ghe
  text: |-
    Implementation landed (TDD, 3 cycles, each RED seen as a compile failure for the missing type, then GREEN):
    - `LibGit2` layer: `LibGit2` (one `git_libgit2_init` via `static let`, `check`, `makeHandle`, last error text), `LibGit2Error` (code + libgit2 text, `isNotFound`), `LibGit2Repository` (owns `git_repository *`, frees in `deinit`, discovery with `git_repository_open_ext` and no flags, `workDirectory`). Typed throws `throws(LibGit2Error)`.
    - `GitContext` (struct): `root`, `pathGuard` (same rules as `FileContext`), `repository: Result<GitRepositoryLocation, CorrectiveRejection>`. Corrections: not in a repository, bare repository, cannot open (with libgit2 text).
    - `GitRepositoryLocation`: `realpath` work folder (spike fact 1) and root parts; `rootRelativePath(fromRepositoryPath:)` (nil outside the root), `repositoryPath(fromRootRelativePath:)` (lexical; nil for an absolute path or above the work folder).
    - `GitCapability` (noun `git`, `tools` empty, internal `context`) and `MultiTool.Builder.withGit(root:)`.
    - `TemporaryGitRepository` in `MultitoolTestSupport`: init (sets HEAD to `refs/heads/main` itself, spike fact 2), `write`, `commit`, `createBranch`. It checks each call through the `LibGit2` layer, so there is no second copy of the error code. `MultitoolTestSupport` now links `gitProducts`.

    Discoveries:
    - A folder with `HEAD`, `objects/`, `refs/` and `config` `bare = true` is a bare repository for libgit2: `git_repository_workdir` gives NULL. A `.git` FILE that is not a `gitdir:` link makes `git_repository_open_ext` fail with a code that is not `GIT_ENOTFOUND`. `core.worktree` in `.git/config` moves the work folder away from the root. The tests use these three to reach each branch of `GitContext`.
    - The nested `IntegrationTests` package builds with the new link (`swift build --build-tests`, only the known mlx-swift bundle warning).
  timestamp: 2026-10-06T16:04:46.624353+00:00
- actor: claude-code
  id: 01m48zbsnftmb5qk0w0s43s605
  text: |-
    ### implement — changed
    - evidence: 12 files. New: Sources/FoundationModelsMultitool/Capabilities/Git/{GitCapability,GitContext,GitRepositoryLocation}.swift, Capabilities/Git/LibGit2/{LibGit2,LibGit2Error,LibGit2Repository}.swift, Tests/Support/MultitoolTestSupport/TemporaryGitRepository.swift, Tests/FoundationModelsMultitoolTests/{GitCapabilityTests,GitContextTests,LibGit2RepositoryTests,TemporaryGitRepositoryTests}.swift. Changed: Package.swift (MultitoolTestSupport links gitProducts, doc comments), Surface/MultiToolBuilder+Capabilities.swift (withGit(root:)). `swift build --build-tests`: 0 errors, only the known mlx-swift "missing creator for mutated node" warning. `swift test`: 1881 tests in 159 suites pass (was 1854 in 155). `IntegrationTests` `swift build --build-tests`: complete, same known warning only.
    - next: /review. The task stays in `doing`.
  timestamp: 2026-10-06T16:04:50.479716+00:00
- actor: claude-code
  id: 01m48zfmgq13gmqpmhf1nhy5cb
  text: |-
    ### test - green
    - evidence: swift build --build-tests - Build complete, exit 0. swift test - 1881 tests in 159 suites passed, 0 failed, 0 skipped. IntegrationTests: swift build --build-tests - Build complete, exit 0.
    - warnings: only the known dependency warning "missing creator for mutated node" for mlx-swift_Cmlx.bundle (existed before this change). No warning comes from this repo's own files.
    - next: review
  timestamp: 2026-10-06T16:06:56.279520+00:00
- actor: claude-code
  id: 01m48zg4xxgr26gwvsvbsy4q07
  text: |-
    ### commit — changed
    - evidence: one local commit "feat: add the git capability on libgit2" holds the Git capability sources, the test support, 4 test suites, Package.swift, the builder change, and the .kanban changes. The sha is in the final step record; this comment is inside the commit, so it cannot name the sha.
    - next: review. Nothing was pushed.
  timestamp: 2026-10-06T16:07:13.085314+00:00
depends_on:
- 01M48V7FH0DA0YA7D28TJV0B4Z
position_column: doing
position_ordinal: '80'
title: 'git: GitCapability, GitContext, and withGit(root:)'
---
## Goal

Make the base of the `git` capability (git.md, "Proposed shape", decisions 8, 9, and 10). It has no verb yet. Each verb task adds its verb to `GitCapability.tools`.

## Where

- Model: `Sources/FoundationModelsMultitool/Capabilities/Files/FilesCapability.swift` and `FileContext.swift`.
- Builder short forms: `Sources/FoundationModelsMultitool/Surface/MultiToolBuilder+Capabilities.swift` (`withFiles`).
- Path rules: `Capabilities/Files/PathGuard.swift`.
- libgit2 model: `Marketplace/Git/LibGit2Transport.swift` in FoundationModelsExtras (init call and error text). Read the spike comments on `^tjv0b4z` for how each C pointer is freed.

## Work

1. New folder `Sources/FoundationModelsMultitool/Capabilities/Git/`.
2. The internal `LibGit2` layer in `Capabilities/Git/LibGit2/` (git.md decision 10). It is the only code that calls the C API (`import libgit2`). It calls `git_libgit2_init` one time, owns each C pointer (free in `deinit` or `defer`), and changes each negative return code into a Swift error with the text of `git_error_last`. In this task, add only what the base needs: open a repository from a path with discovery (`git_repository_discover` / `git_repository_open_ext`), and read its work directory. The verb tasks add their own functions to this layer.
3. `GitCapability: Capability` with `noun = "git"` and `tools: [any Tool]`. Off by default.
4. `GitContext`: holds the root, one `PathGuard` with the same rules as `files`, and the path of the repository that contains the root. It does NOT hold an open libgit2 handle (libgit2 objects are not `Sendable`); each verb opens, uses, and frees them inside one call. The root can be a subfolder of the repository. Give a helper that changes a repository path into a path relative to the root, and the other way.
5. If the root is not in a repository, do not throw at construction. Each verb answers a `correction` in band ("the root is not in a git repository").
6. `MultiTool.Builder.withGit(root:)`: the short form of `withCapability(GitCapability(root:))`.
7. Test support: a helper that makes a temporary repository for one test (init, write files, commit, branch). Put it where the unit tests and the integration tests can use it (see `MultitoolTestSupport` in `Package.swift`). The helper uses libgit2 (no `git` binary), in the pattern of `GitFixtureRepository` in FoundationModelsExtras `Tests/MarketplaceFixtures`.

## Tests

- `withGit(root:)` claims the `tools.git` namespace; a second registration fails at `buildRegistry()`.
- A host with no `withGit` renders no `tools.git`.
- A root in a subfolder finds the repository above it.
- A root outside any repository gives no throw at build time.
- The `LibGit2` layer: an error from libgit2 becomes a Swift error with the libgit2 text.

## Acceptance

- `swift build` and `swift test` pass with no new warnings. #git