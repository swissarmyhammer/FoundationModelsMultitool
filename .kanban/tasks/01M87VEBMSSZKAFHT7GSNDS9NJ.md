---
assignees:
- claude-code
position_column: done
position_ordinal: '80'
title: 'ShellState: remove the temporary fallback store at the end of the state'
---
## Problem
`ShellState.resolveDirectory` uses `<temporary directory>/.shell-<sessionID>` when the preferred store directory cannot be written to. Nothing removes that folder. It is a product leak, though it is rare.

## Fix
- `ShellState` holds `temporaryFallback: URL?`.
- The `deinit` of the actor removes the fallback. Its name holds the session id of the state, so no later store reads it.
- A store directory that the state asked for stays.

## Tests
- `theEndOfAStateRemovesItsTemporaryFallback`
- `theEndOfAStateKeepsItsPreferredStore`