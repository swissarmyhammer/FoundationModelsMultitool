---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0rgsz79zrab6d9wr1kgw5rp
  text: |-
    Research. The path resolver moved since this card was written: `ShellRunner.resolvedDirectory(path:)` now trims a trailing separator and then calls `resolvedPath`, the ONE module resolver declared in `SeatbeltSandbox.swift`. `resolvedPath` is `realpath(3)`, and its own doc comment already states the contract correctly. So the disagreement the card names is only between `CommandSandbox` and the rest of the module, and `CommandSandbox` is the file that was wrong.

    Each mention of the resolver in `Sources/FoundationModelsMultitool/Capabilities/Shell/` was read:
    - `SeatbeltSandbox.resolvedPath` — already correct; states the Foundation resolver runs the other way. No change needed.
    - `SeatbeltSandbox` type doc, `Options.init`, `path(_:isInside:)` — each names `realpath(3)` or `resolvedPath`. Agree already.
    - `ShellRunner.resolvedSandboxDirectories` and `resolvedDirectory(path:)` — each names `resolvedPath`. Agree already.
    - `ShellDecisionStore.storageIdentity(of:)` and `lockURL(forDecisionsAt:)` — these DO use `URL.resolvingSymlinksInPath()`, and that is correct there: the question is file IDENTITY, not the path Seatbelt matches, and no path of that file becomes a sandbox grant. The two uses read as a contradiction with "the one resolver of this module", so `storageIdentity(of:)` now says in one paragraph why the sandbox precondition does not reach it. `lockURL` already points the reader at `storageIdentity(of:)`.

    TDD record. The new test was watched RED: `resolvedPath` was temporarily swapped for `URL(fileURLWithPath: path).resolvingSymlinksInPath().path` — the exact defect the card describes — and the new test failed, both halves flipping (the Foundation form granted, the `realpath(3)` form refused), beside `the shared resolver gives the form Seatbelt matches`. The resolver was restored and both went green. The test is therefore not vacuous: it fails when the wrong resolver is in use.

    The test uses the fixed `/tmp` ↔ `/private/tmp` pair rather than a `$TMPDIR` scratch directory. Two suite tests already pin that pair as a host invariant, so the new test rests on constants the suite holds rather than on a fresh host assumption; a scratch directory under `$TMPDIR` would make the test red on a host where the two forms happen to agree.
  timestamp: 2026-08-23T23:55:29.897498+00:00
- actor: claude-code
  id: 01m0rgtswfaz8v6s6yb72w7kk4
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsMultitool/Capabilities/Shell/CommandSandbox.swift, Sources/FoundationModelsMultitool/Capabilities/Shell/ShellDecisionStore.swift, Tests/FoundationModelsMultitoolTests/SeatbeltSandboxTests.swift. 5 of 5 acceptance and test items checked. `swift test --filter SeatbeltSandbox` → 22 tests, 1 suite, passed. `swift test` → 589 tests, 46 suites, passed, 0 failed, 0 skipped. `swift build --build-tests` → no new warning. `SeatbeltSandbox.swift` is byte-for-byte unchanged; the temporary resolver swap for the RED step was reverted.
    - next: `/review`
  timestamp: 2026-08-23T23:55:57.199956+00:00
- actor: claude-code
  id: 01m0rh3m7d83sx59p5jcgvz24c
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit efcfaed) — 0 findings, 0 confirmed, 0 refuted, 7 attempted, 0 failed. 3 files reviewed; 4 `.kanban/` files excluded by `.reviewignore`.
    - next: task moved to `done`.
  timestamp: 2026-08-24T00:00:46.317655+00:00
- actor: claude-code
  id: 01m0rh46zyrtra5dnfw9cvvw4p
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 3 files (Capabilities/Shell/CommandSandbox.swift, Capabilities/Shell/ShellDecisionStore.swift, Tests/SeatbeltSandboxTests.swift)
    - test: green — swift test, 589 passed in 46 suites, 0 failed, 0 skipped
    - commit: efcfaed fix(shell): name realpath(3) alone as the CommandSandbox path resolver
    - review: clean — zero findings; the task is in done
  timestamp: 2026-08-24T00:01:05.534381+00:00
position_column: done
position_ordinal: e680
title: Correct the path-resolution contract on CommandSandbox
---
## What

The doc comment on `CommandSandbox`
(`Sources/FoundationModelsMultitool/Capabilities/Shell/CommandSandbox.swift`)
tells each caller to put each path through "`realpath(3)` or
`URL.resolvingSymlinksInPath()`". The second one is wrong on macOS, and the
work on ^3qhrkey measured it.

`URL.resolvingSymlinksInPath()` takes the `/private` prefix OFF. Thus:

- `URL(fileURLWithPath: "/private/tmp").resolvingSymlinksInPath().path` gives
  `/tmp`.
- A directory under `$TMPDIR` stays as `/var/folders/…`, and `/var` is itself
  a symbolic link to `/private/var`.

Seatbelt matches the path of the vnode that the KERNEL resolved. Thus the form
that Foundation gives back is the form Seatbelt cannot match. Measured on this
host: a working directory in the `/var/folders/…` form is refused as outside
the roots, because `SeatbeltSandbox.Options` resolves each root with
`realpath(3)` and gets `/private/var/folders/…`.

The doc comment on `SeatbeltSandbox` already states this correctly. The two
files disagree, and the contract stands on `CommandSandbox`.

## Acceptance Criteria

- [x] The precondition on `CommandSandbox` names `realpath(3)` alone.
- [x] It states why `URL.resolvingSymlinksInPath()` does NOT answer the
      precondition, with the measured examples above.
- [x] Each other mention of the resolver in
      `Sources/FoundationModelsMultitool/Capabilities/Shell/` agrees.

## Tests

- [x] A test shows that a path which only `URL.resolvingSymlinksInPath()`
      resolved is refused, and that the `realpath(3)` form of the same
      directory is granted.
- [x] `swift test` passes with no new failure and no new warning. #eventplan #phase-2