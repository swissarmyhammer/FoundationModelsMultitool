---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0sy31nxf0pcjwm8es1k983c
  text: |-
    Research done.

    Facts measured in the tree:
    - `ShellDecisionStore` and `ShellPolicy` are in NO file of `Sources/` or `Tests/`. The only text that names them is `eventplan.md`. So `^6e4x8nw` did remove them.
    - `Yams` is in no manifest. No YAML parser is in the package now.
    - The four members have no reader in `Sources/`. The one file that reads them is `ShellDotfolderTests.swift`.
    - `ShellState.swift` reads `currentDirectory()`. That is the one live use in `Sources/`.
    - `userURL(fileName:)` and `projectURL(fileName:)` also have no reader in `Sources/`. They are NOT on this card, thus I leave them. This needs a card of its own.
    - `SeatbeltSandbox.Options` holds `writableRoots` and `extraWritePaths`. Its doc comment says "This is configuration the host supplies, and it is fixed when the `SeatbeltSandbox` value is made." The host today is code. Only tests make an `Options` value. There is no reader of a file on disk.

    Rule that governs the decision (`dead-code-swift`, periphery, `--retain-public`):
    `ShellDotfolder` is `internal`, thus `--retain-public` gives it no cover. The run uses `--build-tests`, thus the test targets stay in the INDEX and count as callers, and `--report-exclude` keeps them out of the report. So a member a test reads is not reported dead. A member no file reads at all IS reported, and the only answer periphery takes is `// periphery:ignore` on its own line, with the reason on a line above it.

    The decision for each of the four members:
    - `configFileName` — KEEP. The write confinement of `SeatbeltSandbox.Options` must come from somewhere, and the two layer resolvers of this type exist to find such a file. The reason goes in the doc comment.
    - `decisionsFileName` — DELETE. The decision store is gone and the permission card is cancelled, thus no reader will come.
    - `lockFileSuffix` — DELETE. It named the sidecar the atomic rewrite of the decision store locked. Nothing rewrites a file of this dotfolder now.
    - `lockFileMode` — DELETE. Its own doc comment gives its reason as "a test that stands in for a second process must take the lock on the same terms the store does". That store is gone.
  timestamp: 2026-08-24T13:06:53.245555+00:00
- actor: claude-code
  id: 01m0sycsdewgzczq1fhd6qxfw3
  text: |-
    The red-green cycle, and what stood in for a failing assertion.

    A deletion has no assertion that can go red: a member that is gone is a compile
    error, not a test failure. The tool that owns the question gave the red instead.
    `periphery` is the `dead-code-swift` validator, and it answers exactly this.

    1. RED. I put the test file in its intended shape first, with no reference to
       any of the three members I meant to delete. I then built with
       `swift build --build-tests` and ran the periphery scan the validator runs.
       It reported three lines, and only three:
       - `ShellDotfolder.swift:43:16: warning: Unused property 'decisionsFileName'`
       - `ShellDotfolder.swift:51:16: warning: Unused property 'lockFileSuffix'`
       - `ShellDotfolder.swift:64:16: warning: Unused property 'lockFileMode'`

       It did NOT report `configFileName`. That is the measurement that confirms the
       decision set: the scan indexes the test targets, thus a member a test reads
       has a caller, and `configFileName` keeps three readers in the suite.

    2. GREEN. I then deleted the three members and rewrote the header. The same scan
       reports 0 lines for `ShellDotfolder`.

    Results:
    - `swift test --filter ShellDotfolder` — 5 tests, 1 suite, passed.
    - `swift test --filter ShellState` — 33 tests, 2 suites, passed.
    - `swift test` — 553 tests, 45 suites, passed. No failure, and a grep of the
      whole run for `warning`, `error:`, `failed` and `✘` matched nothing.
    - `check working` diagnostics — 0 errors, 0 warnings.
    - `grep` over `Sources` and `Tests` for `decisionsFileName`, `lockFileSuffix`,
      `lockFileMode` and `decisions.yaml` — no match.
    - `grep` over `ShellDotfolder.swift` for `policy`, `decision` and `lock` — no
      match.

    One thing I checked and left alone. `swift format lint --strict` reports
    `[Indentation] unindent by 2 spaces` over my two files. It reports the same over
    untouched files, `ShellState.swift` among them. The package carries no
    `.swift-format` file, thus the lint runs on the 2-space default while the whole
    repository is written with 4 spaces. This is pre-existing and it is not this
    card's work. My two files keep the 4-space style of the code around them.

    New work found and filed as `^jyddp2n`: `userURL` and `projectURL` also have no
    caller in `Sources/`. They are outside this card, thus I left them as they are.
    periphery stays silent about both, because the tests call them.

    ### implement — changed
    - evidence: 2 source files — `Sources/FoundationModelsMultitool/Capabilities/Shell/ShellDotfolder.swift` (header rewritten, 3 members deleted, `configFileName` kept with its reason), `Tests/FoundationModelsMultitoolTests/ShellDotfolderTests.swift` (lock sidecar test and its `expectedLockFileMode` constant removed, two tests moved off `decisionsFileName`). `swift test` 553 passed / 0 failed / 0 warnings. periphery 0 findings for `ShellDotfolder`.
    - next: `/review`
  timestamp: 2026-08-24T13:12:12.462473+00:00
- actor: claude-code
  id: 01m0symqtswb7kytps63pxxd88
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (bde42e6) — 0 findings, 0 confirmed, 0 refuted, 7 attempted, 0 failed. 2 files reviewed; 6 `.kanban/` files excluded by `.reviewignore`.
    - next: task moved to done. No prior Review Findings section, and each checklist item is marked.
  timestamp: 2026-08-24T13:16:32.985005+00:00
- actor: claude-code
  id: 01m0synabw36dbz0fhtz7cq9m6
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 2 files (Capabilities/Shell/ShellDotfolder.swift, Tests/ShellDotfolderTests.swift). decisionsFileName, lockFileSuffix and lockFileMode deleted; configFileName kept with the written reason that it is where the sandbox write roots are meant to come from. Yams was not re-added.
    - test: green — swift test, 553 passed in 45 suites, 0 failed, 0 skipped. The fall from 554 is the deleted lock sidecar test. LSP diagnostics on the working changes give 0 errors and 0 warnings.
    - commit: bde42e6 refactor(shell): retire unused ShellDotfolder members
    - review: clean — zero findings; the task is in done
    - follow-up filed: ^jyddp2n — userURL and projectURL also have no caller in Sources/, and they are the stated reason configFileName was kept, thus the two are bound together.
  timestamp: 2026-08-24T13:16:51.964890+00:00
depends_on:
- 01M0SVAZ3WJH2BQFJSA6E4X8NW
position_column: done
position_ordinal: ea80
title: Retire the ShellDotfolder members that only the permission system used
---
## What

`Sources/FoundationModelsMultitool/Capabilities/Shell/ShellDotfolder.swift`
still describes the deleted design in its header: *"`config.yaml`, which holds
the stacked rules the policy reads, and `decisions.yaml`, which holds the
remembered 'allow always' and 'reject always' answers the decision store reads
and writes."*

After `^6e4x8nw`, four members have no reader in `Sources/`:

- `decisionsFileName = "decisions.yaml"` — no consumer at all.
- `lockFileSuffix` and `lockFileMode` — the only consumers were
  `ShellDecisionStore.swift`, which `^6e4x8nw` deletes.
- `configFileName = "config.yaml"` — its reader was `ShellPolicy`,
  and that card is cancelled, thus no reader will come.

The one live use of the type that stays is `ShellState.swift`, which calls
`currentDirectory()`.

For **each** of the four members, either delete it with its tests, or keep it
and write the reason in the doc comment. Do not leave a member with no reader
and no note. `configFileName` deserves real thought rather than a reflex delete:
the sandbox write roots have to be configured from somewhere, and a shell
`config.yaml` may still be the answer even with no policy. Decide, and record
the decision in the file.

Update the tests to match:
`Tests/FoundationModelsMultitoolTests/ShellDotfolderTests.swift` pins the dead
artifacts at `projectURL(fileName: decisionsFileName)`, `config.yaml.lock`, and
`decisions.yaml.lock`.

Rewrite the file header so it describes what the dotfolder holds now.

## The decision that was made

- `configFileName` — **KEPT**, with the reason in its doc comment. The write
  confinement of `SeatbeltSandbox.Options` is stated there as configuration the
  host supplies, and code is the only host that supplies it today. The two
  layer resolvers of `ShellDotfolder` exist to find such a file, and this
  constant is the one name they resolve. The doc comment also states plainly
  that nothing reads the file yet and that no YAML parser is a dependency of
  the package right now.
- `decisionsFileName` — **DELETED**. The decision store is gone and the
  permission card is cancelled, thus no reader will come.
- `lockFileSuffix` — **DELETED**. It named the sidecar that the atomic rewrite
  of the decision store locked. Nothing rewrites a file of this dotfolder now.
- `lockFileMode` — **DELETED**. Its own doc comment gave its reason as a test
  that stands in for a second process against a store that no longer exists.

## Acceptance Criteria

- [x] Each of the four members is deleted, or kept with a written reason in its
      doc comment.
- [x] The file header names no policy and no decision store.
- [x] `ShellDotfolderTests.swift` pins nothing that was deleted.
- [x] `ShellState.swift` still builds and its suite passes.
- [x] The file names `decisions.yaml` nowhere, unless a written reason keeps it.

## Tests

- [x] `Tests/FoundationModelsMultitoolTests/ShellDotfolderTests.swift` updated —
      the cases for deleted members are removed, and the cases for kept members
      stay green.
- [x] `swift test --filter ShellDotfolder` passes.
- [x] `swift test --filter ShellState` passes.
- [x] `swift test` passes with no new failure and no new warning.

## Workflow
- Use `/tdd` — change the tests to the intended shape first, watch them fail,
  then change the source. #phase-2 #eventplan