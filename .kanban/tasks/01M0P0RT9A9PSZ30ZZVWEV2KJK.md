---
assignees:
- claude-code
depends_on:
- 01M0NAHMQY32H781N3BJ5MRN00
position_column: todo
position_ordinal: '9180'
title: Pin the default decisions file beside the config of each layer
---
## What

`^desmgsm` ported `ShellDecisionStore`. One sibling test could not come with
it, because it needs `ShellPolicy`:
`decisionsFileSitsBesideTheConfigInEveryDefaultLayer`
(`../FoundationModelsShelltool/Tests/ShellToolTests/ShellPolicyDecisionTests.swift:777-791`).

That test makes a default `ShellPolicy` and asserts that
`policy.decisions.userDecisionsURL` and `policy.decisions.projectDecisionsURL`
each sit beside the `config.yaml` of the same layer.

Today nothing in this repository pins where a default store writes. Each store
in the test suite gets its layer URLs from the test. Thus the store and the
configuration could come to disagree about what a layer is, and no test would
say so. A remembered "always" answer that goes to a folder that the
configuration does not read is a permanent grant in a place that no person
looks at.

Port the test after `^j5mrn00` lands `ShellPolicy`.

## Acceptance Criteria

- [ ] A test in this repository asserts the default decisions file of the user
      layer and of the project layer.
- [ ] The test makes a default `ShellPolicy`. It does not make a store with
      explicit URLs.
- [ ] The expected URL comes from `ShellPolicy.defaultUserConfigURL()`,
      `ShellPolicy.defaultProjectConfigURL()` and
      `ShellDotfolder.decisionsFileName`. There is no path literal in the test.
- [ ] The test reads no file, thus it cannot read the real `~/.config/shell` of
      the developer.

## Tests

- [ ] `swift test --filter ShellPolicy` passes.
- [ ] `swift test` passes with no new failure and no new warning. #phase-2 #eventplan