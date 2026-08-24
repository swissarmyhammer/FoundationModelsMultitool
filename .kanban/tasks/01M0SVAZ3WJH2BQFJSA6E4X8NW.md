---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0swhhdszbk0wnhyrq4w5d94
  text: |-
    Research before the delete:

    - `ShellDecisionStore` and `ShellPolicyError` had no reader in `Sources/` other
      than each other. `ShellPolicyError` names `ShellDecisionStore.Scope` in one
      case, thus the two must go together.
    - `ShellDecisionStore.swift:254` held the only `import Yams` of `Sources/`. No
      `ShellPolicy` type exists in the tree, thus the manifest doc that said
      "`ShellPolicy` imports its `Yams` module" described code that was never
      written.
    - `TestScratch` has exactly the 5 remaining caller files the card names.
    - `Package.resolved` is in `.gitignore`, thus the removed `Yams` entry needs no
      commit.
    - `eventplan.md:506` still names the remembered-"always" store. That line
      belongs to `^pqe3khv`, thus this task leaves it alone.

    The `Yams` decision — REMOVE, not keep:

    The card asked to decide and not to leave the question open. `Yams` is removed
    from the library target, from the unit test target, and from the package
    dependencies, and the `Yams` reach test in `DependencyReachTests` is removed
    with it. The reasons:

    1. After the delete no source file imports `Yams`. The only remaining importer
       was `DependencyReachTests`, which proves the link and nothing more. To keep
       a dependency whose one consumer is the test that proves the dependency
       resolves is circular, and the card names that shape as insufficient.
    2. `^5325spr` may keep `ShellDotfolder.configFileName` ("config.yaml") for the
       sandbox write roots. That is not a reason to keep the dependency now: a
       `.package(url:exact:)` line plus one product entry re-adds it in full when a
       reader for that file is actually written.

    `shellProducts` stays as a named array of one product, because the library
    target and the unit test target both link it.
  timestamp: 2026-08-24T12:39:50.969534+00:00
- actor: claude-code
  id: 01m0swj0kp6p8fzdshs1ybnnwr
  text: |-
    ### implement — changed
    - evidence: 6 files. Deleted with `git rm` (NOT `git revert`, because `efcfaed`
      edited `ShellDecisionStore.swift` after `964a2d5`/`305d1cd`):
      `Sources/FoundationModelsMultitool/Capabilities/Shell/ShellDecisionStore.swift`
      (1072 lines),
      `Sources/FoundationModelsMultitool/Capabilities/Shell/ShellPolicyError.swift`
      (39 lines),
      `Tests/FoundationModelsMultitoolTests/ShellDecisionStoreTests.swift`
      (1258 lines).
      Edited: `Package.swift` (Yams removed — the constant, the product, the
      `.package(url:)` line, and the three doc sites that named `ShellPolicy`,
      `ShellDecisionStore` or two shell packages);
      `Tests/FoundationModelsMultitoolTests/DependencyReachTests.swift` (the Yams
      import, the `ShellRule` record, the Yams test, and the suite doc);
      `Tests/FoundationModelsMultitoolTests/Fixtures/ShellStoreFixtures.swift`
      (`WarningRecorder` gone, `TestScratch` kept, header and one `- Returns:` line
      rewritten because both named the deleted store).
      Totals: 25 insertions, 2449 deletions.
    - verification:
      `swift build --build-tests` — Build complete, exit 0. One warning, and it is
      present on the unmodified tree too (measured by stashing the change and
      rebuilding): `missing creator for mutated node: … mlx-swift_Cmlx.bundle`. No
      new warning.
      `swift test` — 554 tests in 45 suites passed. Before the change, measured on
      the stashed tree: 595 tests in 46 suites. The fall of 41 is exactly the 40
      tests of the deleted suite plus the 1 Yams reach test.
      The 5 `TestScratch` suites: OutputBuffer 38, SeatbeltSandbox 22,
      ShellHistoryOps 13, ShellRunner 27, ShellState 33 — all passed.
      `swift test --filter DependencyReach` — 1 test in 1 suite passed.
      `grep -r "ShellDecisionStore\|ShellPolicyError" Sources Tests Package.swift`
      — nothing. `grep -r "Yams" Sources Tests Package.swift` — nothing.
      `grep -r "WarningRecorder" Sources Tests` — nothing.
    - next: `/review`
  timestamp: 2026-08-24T12:40:06.518906+00:00
- actor: claude-code
  id: 01m0swy4ep08n19wc1a91s40wz
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (3695633) — 0 findings, 0 confirmed, 0 refuted, 7 attempted. 6 files reviewed. The Swift hygiene rules declined 9 items because the files they name are deleted by this change; that is the intent of the change, thus no finding.
    - next: none. Task moved to `done`.
  timestamp: 2026-08-24T12:46:43.670365+00:00
- actor: claude-code
  id: 01m0swyv2zy663b0w6ayb957p8
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 6 files, 25 insertions and 2449 deletions. Deleted ShellDecisionStore.swift, ShellPolicyError.swift, ShellDecisionStoreTests.swift; edited Package.swift, DependencyReachTests.swift, Fixtures/ShellStoreFixtures.swift. The Yams dependency is removed entirely.
    - test: green — swift test, 554 passed in 45 suites, 0 failed, 0 skipped. The fall from 595 in 46 is the deleted suite plus the Yams reach test.
    - commit: 3695633 refactor(shell): delete ShellDecisionStore and remembered-answer machinery
    - review: clean — zero findings; the task is in done
  timestamp: 2026-08-24T12:47:06.847483+00:00
position_column: done
position_ordinal: e880
title: Delete ShellDecisionStore and the remembered-answer machinery
---
## What

Decision 2026-08-24: the shell capability has no ask-permission semantics. The
seatbelt sandbox is the only gate on what a shell command may do. The store that
remembers "always allow" / "always deny" answers thus has no reason to exist,
because no question is ever asked.

Delete:

- `Sources/FoundationModelsMultitool/Capabilities/Shell/ShellDecisionStore.swift`
- `Sources/FoundationModelsMultitool/Capabilities/Shell/ShellPolicyError.swift`
  — both of its cases (`noStorageForScope`, `unreadableDecisionsFile`) are about
  the decisions file, thus nothing is left when the store goes.
- `Tests/FoundationModelsMultitoolTests/ShellDecisionStoreTests.swift`

Edit:

- `Tests/FoundationModelsMultitoolTests/Fixtures/ShellStoreFixtures.swift` —
  remove `WarningRecorder` (line 83), which only the store tests use. **Keep
  `TestScratch`** (line 38).
- `Package.swift:178-179` — the manifest doc says *"`ShellPolicy` imports its
  `Yams` module for the stacked policy files, and `ShellDecisionStore` imports
  it for the remembered decisions."* Both types are gone, thus rewrite it.

**Decide the `Yams` dependency in this task.** `ShellDecisionStore.swift:254` is
the only `import Yams` in `Sources/`. After the delete the library target has no
consumer of the product, and only
`Tests/FoundationModelsMultitoolTests/DependencyReachTests.swift` still imports
it, which proves the link and nothing more. Either remove `Yams` from the
library target and correct `DependencyReachTests`, or state in `Package.swift`
why it stays. Do not leave it undecided.

**Use a delete commit, not a revert.** The store arrived in `964a2d5` and
`305d1cd`, but `efcfaed` later edited `ShellDecisionStore.swift`, thus
`git revert` of the two conflicts.

Do not touch `elicit()` or the MCP elicitation passthrough. They are a general
capability for a question in the middle of a run, and not the permission system.

**Decision taken 2026-08-24: `Yams` is REMOVED.** It is gone from the library
target, from the unit test target, from the package dependencies, and its reach
test in `DependencyReachTests` is gone with it. See the comment thread for the
two reasons.

## Acceptance Criteria

- [x] The three files above are gone from the working tree.
- [x] `WarningRecorder` is gone. `TestScratch` stays, and its **5** remaining
      caller files build: `OutputBufferTests.swift`, `SeatbeltSandboxTests.swift`,
      `ShellHistoryOpsTests.swift`, `ShellRunnerTests.swift`,
      `ShellStateTests.swift`.
- [x] `grep -r "ShellDecisionStore\|ShellPolicyError" Sources Tests Package.swift`
      finds nothing.
- [x] `Package.swift` names neither deleted type.
- [x] The `Yams` dependency is either removed from the library target or kept
      with a written reason in `Package.swift`.

## Tests

- [x] `swift build --build-tests` succeeds with no error and no new warning.
- [x] `swift test` passes with no new failure and no new warning. Record the new
      count; it falls by the tests the deleted file held. 595 tests in 46 suites
      before, 554 tests in 45 suites after: 40 tests of the deleted suite plus
      the 1 Yams reach test.
- [x] The 5 suites that use `TestScratch` still pass.
- [x] `swift test --filter DependencyReach` passes, whichever way the `Yams`
      question is answered.

## Workflow
- This task deletes code. `/tdd` does not apply: the guard that the names stay
  gone is `^pqe3khv`. Verify by build and by the full suite. #phase-2 #eventplan