---
assignees:
- claude-code
depends_on:
- 01M0SVAZ3WJH2BQFJSA6E4X8NW
- 01M0SVC2NKA2DA58M3E98ZGZYQ
- 01M0SVY1BGMH3DKQHY05325SPR
position_column: todo
position_ordinal: '9580'
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

- [ ] Expose the repository root on `RepositoryFile`.
- [ ] Add a walk that gives every `.swift` file under a relative directory.
- [ ] Build the guard on that walk.

## Acceptance Criteria

- [ ] Neither passage promises `ShellPolicy`, allow/deny/ask, or a remembered
      store.
- [ ] `eventplan.md` records the decision, its reason, and the read-and-network
      limit.
- [ ] `eventplan.md` states that `elicit()` and the MCP passthrough are
      unchanged.
- [ ] `RepositoryFile` exposes the repository root and can walk a directory.
- [ ] A test fails if any banned name returns.

## Tests

- [ ] New `Tests/FoundationModelsMultitoolTests/ShellPermissionRemovalTests.swift`.
- [ ] The banned names are `ShellPolicy`, `ShellDecisionStore`, and
      `ShellPolicyError`. Add `decisions.yaml` unless `^5325spr` kept it with a
      written reason.
- [ ] A test walks `Sources/` and asserts no file holds a banned name. It names
      the offending file and line when it fails.
- [ ] A test does the same over `Tests/`, excluding this guard file itself.
- [ ] A test asserts `eventplan.md` holds no banned name.
- [ ] A test asserts `Package.swift` holds no banned name — it sits at the
      repository root, thus a tree walk over `Sources/` and `Tests/` misses it.
- [ ] `swift test --filter ShellPermissionRemoval` passes.
- [ ] `swift test` passes with no new failure and no new warning.

## Workflow
- Use `/tdd` — write the guard tests first and watch them fail on the current
  text, then edit `eventplan.md` to make them pass. #phase-2 #eventplan