---
assignees:
- claude-code
depends_on:
- 01M0SVAZ3WJH2BQFJSA6E4X8NW
position_column: todo
position_ordinal: '9680'
title: Retire the ShellDotfolder members that only the permission system used
---
## What

`Sources/FoundationModelsMultitool/Capabilities/Shell/ShellDotfolder.swift`
still describes the deleted design in its header: *"`config.yaml`, which holds
the stacked rules the policy reads, and `decisions.yaml`, which holds the
remembered 'allow always' and 'reject always' answers the decision store reads
and writes."*

After `^6e4x8nw`, four members have no reader in `Sources/`:

- `decisionsFileName = "decisions.yaml"` (line 43) — no consumer at all.
- `lockFileSuffix` and `lockFileMode` — the only consumers were
  `ShellDecisionStore.swift:728` and `:876`, which `^6e4x8nw` deletes.
- `configFileName = "config.yaml"` (line 38) — its reader was `ShellPolicy`,
  and that card is cancelled, thus no reader will come.

The one live use of the type that stays is `ShellState.swift:218`, which calls
`currentDirectory()`.

For **each** of the four members, either delete it with its tests, or keep it
and write the reason in the doc comment. Do not leave a member with no reader
and no note. `configFileName` deserves real thought rather than a reflex delete:
the sandbox write roots have to be configured from somewhere, and a shell
`config.yaml` may still be the answer even with no policy. Decide, and record
the decision in the file.

Update the tests to match:
`Tests/FoundationModelsMultitoolTests/ShellDotfolderTests.swift` pins the dead
artifacts at lines 87-95 (`projectURL(fileName: decisionsFileName)`), line 102
(`config.yaml.lock`), and lines 103-105 (`decisions.yaml.lock`).

Rewrite the file header so it describes what the dotfolder holds now.

## Acceptance Criteria

- [ ] Each of the four members is deleted, or kept with a written reason in its
      doc comment.
- [ ] The file header names no policy and no decision store.
- [ ] `ShellDotfolderTests.swift` pins nothing that was deleted.
- [ ] `ShellState.swift:218` still builds and its suite passes.
- [ ] The file names `decisions.yaml` nowhere, unless a written reason keeps it.

## Tests

- [ ] `Tests/FoundationModelsMultitoolTests/ShellDotfolderTests.swift` updated —
      the cases for deleted members are removed, and the cases for kept members
      stay green.
- [ ] `swift test --filter ShellDotfolder` passes.
- [ ] `swift test --filter ShellState` passes.
- [ ] `swift test` passes with no new failure and no new warning.

## Workflow
- Use `/tdd` — change the tests to the intended shape first, watch them fail,
  then change the source. #phase-2 #eventplan