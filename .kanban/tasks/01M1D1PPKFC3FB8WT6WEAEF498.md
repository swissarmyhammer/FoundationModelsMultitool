---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: README has no "### Injected globals" section, so HardeningTests fails on main
---
## What

`swift test` at the root is red on `main` with one issue:

```
✘ Test "README's enumerated 'Injected globals' list is set-equal to the
  runtime-enumerated sandbox globals" recorded an issue at
  HardeningTests.swift:285:6: Caught error: README.md has no
  "### Injected globals" section.
```

The test reads `README.md` for a `### Injected globals` heading and compares
the list under it with the globals the sandbox really installs. `README.md`
carries no such heading now, so the test throws before it can compare
anything.

## Why it matters

The list is the one place a reader learns which globals a snippet gets. While
the heading is absent, nothing holds the README to what the sandbox installs,
and every root `swift test` run is red for a reason that hides a real one.

## What to do

Decide which of the two is correct, then make the other match:

1. put the `### Injected globals` section back in `README.md`, with the
   globals the sandbox enumerates; or
2. if that section is deliberately gone, retire the test and say in the commit
   what now holds the README to the sandbox.

Option 1 is the likely answer: the test exists to stop the two drifting apart.

## Acceptance Criteria

- [ ] `swift test` at the root reports zero issues.
- [ ] The README list and the runtime-enumerated globals are set-equal, or the
      test is retired with a stated replacement.

## Found by

Task `^9kq30r8`, measuring the root suite's baseline on 2026-08-31. It is not
that card's to correct. #eventplan
