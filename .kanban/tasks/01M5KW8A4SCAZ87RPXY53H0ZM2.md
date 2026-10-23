---
assignees:
- claude-code
position_column: done
position_ordinal: ffffffbd80
title: 'Shareable ShellStore: capabilities of one cwd share one shell history'
---
Request from FoundationModelsACPAgent (2026-10-23): ACP sessions in one process that share a cwd share ONE shell store per cwd.

Today `ShellCapability.init` always makes a private `ShellState` with a random sessionID, so two sessions on one `.shell` folder cannot see each other's commands, and `appendLines` uses seekToEnd()+write, so two actors on one log can overwrite each other's lines.

- [ ] public `ShellStore` (final class, Sendable) wrapping `ShellState`, `init(storeDirectory:)`
- [ ] `ShellCapability.init(store:sandbox:outputChunkStream:defaultWorkingDirectory:)`, current init kept; `withShell(store:...)` short form
- [ ] capabilities on one store see every command of the store (ids are run-plane ULIDs, unique already)
- [ ] log appends open with O_APPEND so each line stays whole across stores on one file

Tests first: B lists and reads A's command; concurrent commands leave every line whole; two stores stay separate.