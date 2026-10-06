---
assignees:
- claude-code
depends_on:
- 01M48V7FH0DA0YA7D28TJV0B4Z
position_column: todo
position_ordinal: '8180'
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