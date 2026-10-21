---
assignees:
- claude-code
depends_on:
- 01M5F236W9NXECHBE44PTMVYQZ
position_column: todo
position_ordinal: '8580'
title: 'SessionsTool change ops: start, tag, untag, rename, archive (MT-2)'
---
## What
In `Sources/FoundationModelsMultitool/Capabilities/Sessions/SessionsTool.swift` (design: `session.md` section 8; conventions: EXTRAS-9 rule 7, which needs an op for every graph mutation):
- `start session` takes `agent` and an optional `cwd` and a first message, and calls `SessionDirectory.start`. A model start never opens a tab (D90).
- `tag session`, `untag session` (`addTags`/`removeTags`).
- `rename session` (`setTitle`). This op is new relative to section 8.1; EXTRAS-9 adds it so the agent can do what the UI can (D100).
- `archive session` (D68, D72). It works for any session the caller can see.
- `noLauncher` and `archived` directory errors become correctives.

## Acceptance Criteria
- [ ] Each op works through `tools.sessions.<verb>` over `InMemorySessionDirectory` and changes the directory state
- [ ] `startSession` without a launcher gives a corrective, not a throw
- [ ] `renameSession` exists and its verb name matches the planned graph mutation `renameSession`

## Tests
- [ ] New `Tests/FoundationModelsMultitoolTests/SessionsToolChangeTests.swift`
- [ ] `swift test --filter SessionsTool` passes

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #sessions