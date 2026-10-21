---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5f82b6zw2th65k0nxr090ms
  text: |-
    Picked up. Research notes:
    - `swift package update FoundationModelsExtras` puts Extras at ac1b9f2 (EXTRAS-3/EXTRAS-4 in Sources/FoundationModelsExtras/Sessions/). Package.swift already links `Operations` (1d307c8).
    - `withSessions` will go through `OperationToolCapability` (same path as `withOperationTool(noun:tool:)`), so `SessionsTool` must be `OperationDescribing`. `OperationVerbTool` calls `perform(_:)`, which gives the JSON-encoded output of `OperationTool`; like `AgentsTool.call`, `SessionsTool` decodes that JSON string in both `call` and `perform`, so a snippet gets plain text.
    - `CorrectiveOutcome` lives in FoundationModelsSkills, which Multitool does not link. The ops return plain `String` text for both a result and a corrective (same wire result as AgentsTool's `CorrectiveOutcome<String>` after decoding).
    - session.md 8.2: `read inbox` takes `limit` (default 10), but `SessionDirectory.inbox(of:markRead:)` marks EVERY unread message read and has no limit, so a limit would consume messages the model never sees. The op therefore shows every unread message it marks read and takes no `limit`; a follow-up task records the port change that a limit needs.
    - session.md 8.2: a call with no ToolContext can only read; `read inbox` then gives a corrective (it needs the caller session).
  timestamp: 2026-10-21T12:48:06.367435+00:00
- actor: claude-code
  id: 01m5f8j5d2p8cqhmw3mdswnarg
  text: |-
    Implementation landed (TDD: SessionsToolReadTests failed to compile first, then 12/12 green).
    - New `Capabilities/Sessions/`: `SessionsTool.swift` (public struct, `Tool` + `OperationDescribing`, `init(directory:)`), `SessionsToolContext.swift` (internal, holds `any SessionDirectory`, reads the caller from `ToolContext.current`), `SessionsToolOperations.swift` (`ListSessions`, `CheckSession`, `ReadInbox` as `@Operation`s; TODO(MT-7) at the top), `SessionsToolInput.swift` (forgiving argument readers), `SessionsToolText.swift` (answers + correctives).
    - `MultiTool.Builder.withSessions(_:)` goes through `withOperationTool(noun: "sessions", tool:)`.
    - Gotcha: the default verb aliases of `OperationResolver` map `read` to `get`, so `read inbox` named no operation ("Unknown operation"). `SessionsTool.verbAliases` maps `read` back to `read`.
    - Forgiving reads: session ids in any letter case, `kind`/`state` in any letter case, `limit` clamped to 1...100, `state: archived` turns on `includesRecorded` (an archived session is never live).
    - `check session` counts the unread messages from the checked session to the caller; it omits the line when the call has no caller or the directory does not know the caller.
    - `read inbox` fences each text with a fence longer than any backtick run in it (untrusted input, session.md 10.1).
    - EXTRAS-9 rule 1: the struct holds only the operation tool over the directory; the doc comment states that a later shared part (SessionsGraph, change log) is made once per directory, so `init(directory:)` keeps its shape.
    - Follow-up: ^vehzwv4 (read inbox `limit` needs a port limit).
  timestamp: 2026-10-21T12:56:44.706680+00:00
- actor: claude-code
  id: 01m5f8j7xbx2bg2yjv449h01ar
  text: |-
    ### implement — changed
    - evidence: `swift test --filter SessionsToolReadTests` 12/12 passed; full `swift test` 2573 tests in 223 suites passed, 0 failures; `swift build` no code warnings. 7 files — Sources/FoundationModelsMultitool/Capabilities/Sessions/{SessionsTool,SessionsToolContext,SessionsToolOperations,SessionsToolInput,SessionsToolText}.swift, Sources/FoundationModelsMultitool/Surface/MultiToolBuilder+Capabilities.swift, Tests/FoundationModelsMultitoolTests/SessionsToolReadTests.swift
    - next: /review
  timestamp: 2026-10-21T12:56:47.275164+00:00
- actor: claude-code
  id: 01m5f8yq076x104cygdhqsv2jm
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (7f2020b) — 0 findings, 0 confirmed, 1 refuted, 7 files reviewed, 6 .kanban files skipped by .reviewignore
    - next: none; task moved to done
  timestamp: 2026-10-21T13:03:35.943713+00:00
- actor: claude-code
  id: 01m5f8z56qa0q129we38x6z7bg
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 5 Capabilities/Sessions files, MultiToolBuilder+Capabilities.swift, SessionsToolReadTests.swift
    - test: green — swift test, 2573 tests / 223 suites (run by implement)
    - commit: 7f2020b (docs 3c1c359)
    - review: clean — 0 findings
  timestamp: 2026-10-21T13:03:50.487290+00:00
depends_on:
- 01M5F2FRK43MH90K2KVNK0RXQ2
position_column: done
position_ordinal: ffffffb080
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
- [x] `tools.sessions.listSessions`, `checkSession` and `readInbox` work in a `runCode` snippet over an `InMemorySessionDirectory`
- [x] `read inbox` marks the messages read; a second read gives none
- [x] An unknown session id gives a corrective naming `listSessions`

## Tests
- [x] New `Tests/FoundationModelsMultitoolTests/SessionsToolReadTests.swift` (direct op calls + a snippet through `withSessions`)
- [x] `swift test --filter SessionsTool` passes; `swift build` has no warnings

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #sessions #blocked-external