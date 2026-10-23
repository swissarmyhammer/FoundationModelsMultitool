---
assignees:
- claude-code
position_column: done
position_ordinal: ffffffc180
title: Shell session id is a closure read each time a command runs
---
Request from FoundationModelsACPAgent (2026-10-23, user approved). Tools are built before Router mints the session id, and a model-slot switch keeps the tools across Router sessions.

- [ ] `ShellCapability.init(store:sessionID: @escaping @Sendable () -> String? = { nil }, ...)` and `withShell(store:sessionID:...)` take a closure (replaces the `String?` form)
- [ ] `ShellRunner.sessionID` is the closure, read in `run` when the record starts
- [ ] Test: the closure's value at run time, not at init, is what the record, execute report, getLines and grepHistory show

Tests first in ShellStoreSharingTests.