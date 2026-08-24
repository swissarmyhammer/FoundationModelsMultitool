---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0t0kqzgdy86y0rkscej2vzr
  text: |-
    Research done.

    Facts found:
    - `eventplan.md` is the ONLY file in the repository that still holds a banned name. `Sources/`, `Tests/` and `Package.swift` are already clean (grep over each: no match for `ShellPolicy`, `ShellDecisionStore`, `ShellPolicyError`, `decisions.yaml`). Thus the guard tests over those three fail only if the design comes back, which is what the card asks for.
    - The two passages stand at `eventplan.md` lines 499-508 and 762-766, word for word as the card quotes them.
    - `^5325spr` DELETED `decisionsFileName` (`decisions.yaml`) and KEPT `configFileName` (`config.yaml`) with a written reason in `ShellDotfolder.swift`. Thus `decisions.yaml` joins the ban list, and `config.yaml` must NOT be banned.
    - `ShellDotfolder` today holds `name`, `configFileName`, the two layer resolvers and `currentDirectory()`. `ShellState` roots the per-session history store on `currentDirectory()`. So the `.shell` dotfolder mention in the Phase 2 sentence is still true; it is what the dotfolder holds that changed.
    - `IntegrationTests/` is a nested package outside `Sources/` and `Tests/`. The card names `Package.swift` only, so the guard covers the root manifest and not the nested one.
    - `RepositoryFile` has one member, `read(relativePath:)`. It computes the repository root inline with three `deletingLastPathComponent()` steps and keeps it private.

    Plan: TDD in two cycles. First cycle extends `RepositoryFile` (root + swift-file walk) against new cases in `RepositoryFileTests.swift`. Second cycle writes `ShellPermissionRemovalTests.swift`, watches the `eventplan.md` case fail, then rewrites the two passages.
  timestamp: 2026-08-24T13:50:57.520260+00:00
- actor: claude-code
  id: 01m0t0x663tx8rtyp12xc32037
  text: |-
    Implementation landed. Two TDD cycles, each one watched red before it went green.

    Cycle 1 — the helper. Six new cases in `RepositoryFileTests.swift` failed to compile: "type 'RepositoryFile' has no member 'root'" and "no member 'swiftFiles'". Then `RepositoryFile` got `root`, `swiftFiles(inRelativeDirectory:)` and a private `url(forRelativePath:)` that both public members share, thus the path guard stands in one place. All 7 cases green.

    Cycle 2 — the guard. `ShellPermissionRemovalTests.swift` failed for the right reason on the first run:
    ```
    eventplan.md:501: ShellPolicy
    eventplan.md:764: ShellPolicy
    ```
    The `Sources/`, `Tests/` and `Package.swift` cases passed on that same run, which is the expected state: `^6e4x8nw` and `^5325spr` already cleared those three. Then the two passages of `eventplan.md` were rewritten and all 4 cases went green.

    Two decisions made while writing the code, recorded for the next reader:

    1. **The walk fails loud when it reads nothing.** `swiftFiles(inRelativeDirectory:)` throws `RepositoryFileError.directoryCannotBeWalked` when the path names no directory. The alternative — answer an empty list — makes each guard case pass while it reads no file, which is the one failure mode a guard must not have. `RepositoryFileTests` pins both halves: the walk finds a file nested three levels deep, and it throws for a directory that is not there.

    2. **The guard file excludes itself by `#filePath`, not by name.** The file must spell each banned name to search for it, so the `Tests/` walk drops the one URL that equals `URL(fileURLWithPath: #filePath).standardizedFileURL`. A name match would drop any file that happened to share the name.

    `config.yaml` is NOT on the ban list, and the suite doc comment says why: `^5325spr` kept `ShellDotfolder.configFileName` with a written reason.

    The Phase 2 sentence was also checked against `^5325spr`, as the card asked. The `.shell` dotfolder mention stays true, so the sentence now states what the dotfolder holds today — the history of each session and `config.yaml`, with no reader of that file yet.

    `swift test`: 562 tests in 46 suites, 0 failures, 0 warnings.
  timestamp: 2026-08-24T13:56:06.979030+00:00
- actor: claude-code
  id: 01m0t0xbaqhxvpcsgawm194059
  text: |-
    ### implement — changed
    - evidence: 4 files — Tests/FoundationModelsMultitoolTests/ShellPermissionRemovalTests.swift (new), Tests/FoundationModelsMultitoolTests/RepositoryFile.swift, Tests/FoundationModelsMultitoolTests/RepositoryFileTests.swift, eventplan.md. `swift test --filter ShellPermissionRemoval`: 4 tests, 4 passed. `swift test --filter RepositoryFile`: 7 tests, 7 passed. `swift test`: 562 tests in 46 suites, 0 failures, 0 warnings.
    - next: /review
  timestamp: 2026-08-24T13:56:12.247645+00:00
depends_on:
- 01M0SVAZ3WJH2BQFJSA6E4X8NW
- 01M0SVC2NKA2DA58M3E98ZGZYQ
- 01M0SVY1BGMH3DKQHY05325SPR
position_column: doing
position_ordinal: '8380'
title: Record the sandbox-only decision in eventplan.md and guard it with a test
---
## What

`eventplan.md` still specifies the design that is now deleted. Two passages must
change, or the next planning pass reads them and writes the cards again.

- **Lines 499-508**: *"and `ShellPolicy`. The three policy outcomes stay: allow,
  deny, ask. But the ask outcome changes its meaning… With elicitation always
  available, ask goes through `ToolContext.elicit`, and the remembered-'always'
  store works as designed."*
- **Lines 761-766**, Phase 2: *"`Capabilities/Shell` gets `ShellRunner`,
  `OutputBuffer`, the `.shell` dotfolder, the history operations, and
  `ShellPolicy` with ask routed through `ToolContext.elicit`."* The sentence
  starts at 761, and it also names the `.shell` dotfolder, thus check it against
  whatever `^5325spr` decided.

Replace both with the decision of 2026-08-24, and record the reason, not only
the outcome:

- The shell capability has no permission question and no remembered answer. The
  seatbelt sandbox is the only gate.
- The reason: a denylist over command text is bypassable. The `matchKey` header
  of the deleted store spent 50 lines on exactly this — quoting starts again
  inside `$( )`, `$'…'` reads `\'` — and a lexer that is a little wrong grants
  what nobody granted. The sandbox is a kernel boundary and does not care how a
  command is spelled.
- The limit, stated plainly: the sandbox bounds writing and deleting. Reads are
  free and the network is open, thus exfiltration is not bounded. To change
  either one is a change to the profile.
- The command-length and environment-value checks live in the
  `tools.shell.execute` verb (`^xgnygf8`), and not in a policy layer.
- Keep `elicit()` and the MCP elicitation passthrough exactly as they are. They
  are a general capability, and not the permission system. Say so, because the
  two are easy to confuse.

## The guard needs a helper first

`Tests/FoundationModelsMultitoolTests/RepositoryFile.swift` has one member,
`read(relativePath: String) throws -> String`. It reads one named file, it
cannot walk a directory, and it keeps the repository root private. A guard over
whole trees is not implementable with it as it stands.

So this task extends the helper before it writes the guard:

- [x] Expose the repository root on `RepositoryFile`.
- [x] Add a walk that gives every `.swift` file under a relative directory.
- [x] Build the guard on that walk.

## Acceptance Criteria

- [x] Neither passage promises `ShellPolicy`, allow/deny/ask, or a remembered
      store.
- [x] `eventplan.md` records the decision, its reason, and the read-and-network
      limit.
- [x] `eventplan.md` states that `elicit()` and the MCP passthrough are
      unchanged.
- [x] `RepositoryFile` exposes the repository root and can walk a directory.
- [x] A test fails if any banned name returns.

## Tests

- [x] New `Tests/FoundationModelsMultitoolTests/ShellPermissionRemovalTests.swift`.
- [x] The banned names are `ShellPolicy`, `ShellDecisionStore`, and
      `ShellPolicyError`. Add `decisions.yaml` unless `^5325spr` kept it with a
      written reason.
- [x] A test walks `Sources/` and asserts no file holds a banned name. It names
      the offending file and line when it fails.
- [x] A test does the same over `Tests/`, excluding this guard file itself.
- [x] A test asserts `eventplan.md` holds no banned name.
- [x] A test asserts `Package.swift` holds no banned name — it sits at the
      repository root, thus a tree walk over `Sources/` and `Tests/` misses it.
- [x] `swift test --filter ShellPermissionRemoval` passes.
- [x] `swift test` passes with no new failure and no new warning.

## Workflow
- Use `/tdd` — write the guard tests first and watch them fail on the current
  text, then edit `eventplan.md` to make them pass. #phase-2 #eventplan