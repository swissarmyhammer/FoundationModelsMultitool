---
assignees:
- claude-code
position_column: done
position_ordinal: ffffffbf80
title: Shell results name the session that ran each command
---
Request from FoundationModelsACPAgent (2026-10-23, user approved). On a shared ShellStore, results should say which session ran a command.

- [ ] `ShellCapability.init(store:sessionID:sandbox:outputChunkStream:defaultWorkingDirectory:)` and `withShell(store:sessionID:...)`, `sessionID: String? = nil`
- [ ] `CommandRecord.owner`; `ShellRunner.sessionID` passed to `startCommand(_:commandID:owner:)`
- [ ] `sessionID` on the execute report, `GetLinesResult`, and each `GrepHistoryMatch` (absent when the capability has none)

Tests first in ShellStoreSharingTests.