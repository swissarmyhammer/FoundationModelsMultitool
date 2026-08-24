---
assignees:
- claude-code
position_column: todo
position_ordinal: '9680'
title: Decide the fate of ShellDotfolder.userURL and projectURL, which no Sources file calls
---
## What

Found while doing `^5325spr`, and left alone there because that card scopes to
four constants only.

`ShellDotfolder` has two layer resolvers:

- `userURL(fileName:environment:)`
- `projectURL(fileName:)`

No file of `Sources/` calls either one. The one member of the type that a
`Sources/` file calls is `currentDirectory()`, from `ShellState`.

`periphery` stays silent about both, because `ShellDotfolderTests` calls them
and the scan indexes the test targets. So the tool reports nothing, and the
question is a design question rather than a dead-code finding.

The two resolvers are the reason `configFileName` was kept in `^5325spr`: they
are how a future reader of the shell `config.yaml` finds the file in each of
the two layers. So the answer here is bound to the answer there.

## What to decide

One of these, and write the reason in the file:

1. Keep both, because the config reader that `configFileName` waits for is the
   caller that lands. State that in the doc comment of each one, the way
   `configFileName` states it now.
2. Delete both with their tests, and let the config reader bring back the
   resolution it needs. `configFileName` then has to be looked at again too,
   because the reason its doc comment gives names these two resolvers.

Do not leave the two with no caller and no note.

## Acceptance Criteria

- [ ] `userURL` and `projectURL` are each deleted, or kept with a written
      reason in the doc comment.
- [ ] The reason written on `configFileName` still reads true after the change.
- [ ] `swift test` passes with no new failure and no new warning.
- [ ] `periphery` reports nothing new for `ShellDotfolder.swift`.

#phase-2 #eventplan</description>
<parameter name="tags">["phase-2", "eventplan"]