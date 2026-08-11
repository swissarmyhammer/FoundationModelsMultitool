---
assignees:
- claude-code
position_column: todo
position_ordinal: '8280'
title: Get the tree building again against Router
---
Nothing below can be measured until this is true, so it goes first.

## The state

`swift build` fails inside **Router's own sources**, not ours. Two different errors within minutes, because their agent is mid-edit:

```
RoutedSessionActorRunJournal.swift:85: cannot find 'journaledTerminalCorrelationIDs' in scope
RoutedSessionActorRecording.swift:143:34: missing argument label 'event:' in call
```

We consume Router **by local path** (`.package(path: "../FoundationModelsRouter")`), so their working tree is our build input: a half-finished edit there breaks us instantly. That is the price of the fast local dev loop and is expected, not a Router defect.

## What this card is

Not "fix Router". It is: reach a state where `swift build` and the ungated suite are green, and record what it took, so the three behaviour cards start from a known-good tree.

Expect to have to adapt to their API changes as part of it. Two already landed and needed our side updated: `SessionEvent.textReset` (`^w8dzvee` D2) and `SessionEvent.turnStarted` (`^way106d`), both of which broke exhaustive switches in `ScenarioRunner`.

## Uncommitted work waiting on this

Four files are modified and **unverified** — written while the build was broken, so they have never compiled or run:

- `Sources/FoundationModelsMultitool/Discovery/SearchToolsTool.swift` — both detach clocks answered explicitly
- `Sources/FoundationModelsMultitool/WaitTool.swift` — passed timeout honoured, no host cap
- `Tests/FoundationModelsMultitoolTests/WaitToolTests.swift` — matching assertions
- `Tests/.../Support/ScenarioRunner.swift` — `sampleGenerator` dropped to match `CLIRunner.swift:390`

Verify these before anything else; do not assume they are correct because they were written carefully.

## Also here, since it is the same subject

- [ ] The `Package.swift` local-path dependency is temporary and is an exit blocker on `^tkrdwb8`. `grep -n 'path: "../' Package.swift` must eventually return nothing
- [ ] While it stands, every build emits two SwiftPM warnings: MetadataRegistry and Ranker pull Router by URL while we pull it by path, so one identity has two sources. SwiftPM says this "will be escalated to an error in future versions". Worth knowing it is a countdown, not a permanent nuisance

## Acceptance Criteria

- [ ] `swift build` clean
- [ ] Ungated `swift test` green, both targets, and the counts recorded here
- [ ] The four uncommitted files are either verified and committed, or reverted with the reason stated — never left modified and unbuilt
- [ ] Any Router API change adapted to is named here with its commit, so the next breakage is diagnosed by comparison rather than from scratch #eventplan