---
assignees:
- claude-code
position_column: todo
position_ordinal: '9080'
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

- [ ] The precondition on `CommandSandbox` names `realpath(3)` alone.
- [ ] It states why `URL.resolvingSymlinksInPath()` does NOT answer the
      precondition, with the measured examples above.
- [ ] Each other mention of the resolver in
      `Sources/FoundationModelsMultitool/Capabilities/Shell/` agrees.

## Tests

- [ ] A test shows that a path which only `URL.resolvingSymlinksInPath()`
      resolved is refused, and that the `realpath(3)` form of the same
      directory is granted.
- [ ] `swift test` passes with no new failure and no new warning. #eventplan #phase-2