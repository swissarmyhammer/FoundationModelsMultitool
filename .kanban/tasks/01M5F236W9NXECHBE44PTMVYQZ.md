---
assignees:
- claude-code
depends_on:
- 01M5F2FRK43MH90K2KVNK0RXQ2
position_column: todo
position_ordinal: '8480'
title: SessionsTool skeleton, withSessions, and the read ops (MT-2, MT-9)
---
## What
**Blocked outside this repo:** EXTRAS-3 (`SessionDirectory` port) and EXTRAS-4 (`InMemorySessionDirectory`) in FoundationModelsExtras. Neither is built; the Router session was asked to own them. Start when both are on Extras `main` (`swift package update`). The `Operations` product link and the `Read.swift` header comment are in 01M5F2FRK43MH90K2KVNK0RXQ2.

Design: `session.md` sections 8 and 14 (MT-2, MT-9); conventions EXTRAS-9 (TestudoApp `features/packages/foundationmodels-extras.md`, D115). Files: `Sources/FoundationModelsMultitool/Capabilities/Sessions/SessionsTool.swift`, `Sources/FoundationModelsMultitool/Surface/MultiToolBuilder+Capabilities.swift` (`withSessions`) and the test file.
- New `Sources/FoundationModelsMultitool/Capabilities/Sessions/SessionsTool.swift`: `public struct SessionsTool: Tool` holding an `OperationTool<SessionsToolContext>`; `SessionsToolContext` holds `any SessionDirectory`. Same shape as `AgentsTool` (`FoundationModelsAgents/Sources/FoundationModelsAgents/Tool/AgentsTool.swift:49`).
- Read ops: `list sessions`, `check session`, `read inbox` (marks the messages read, D72). Errors become correctives, never thrown model errors.
- `MultiTool.Builder.withSessions(_ tool: SessionsTool)` registers the same instance under the noun `sessions` (`Surface/MultiToolBuilder+Capabilities.swift`, next to `withOperationTool` at :295).
- Risk facts (MT-7) are out of scope here: MT-1/MT-7 are not built. Leave a TODO naming MT-7.

## Acceptance Criteria
- [ ] `tools.sessions.listSessions`, `checkSession` and `readInbox` work in a `runCode` snippet over an `InMemorySessionDirectory`
- [ ] `read inbox` marks the messages read; a second read gives none
- [ ] An unknown session id gives a corrective naming `listSessions`

## Tests
- [ ] New `Tests/FoundationModelsMultitoolTests/SessionsToolReadTests.swift` (direct op calls + a snippet through `withSessions`)
- [ ] `swift test --filter SessionsTool` passes; `swift build` has no warnings

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #sessions #blocked-external