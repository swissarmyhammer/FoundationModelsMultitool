---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4e1hy9w19zp9z9ph50yqsvk
  text: |-
    Corrections from foundationmodelsacpagent-19 (2026-10-08):
    - The settle period is a SETTING with a default of 6 s. The literal 6 is in one constant only.
    - One setting for the whole hosting layer; each host can change it. It reaches every background tool, `execute` included, and inner calls.
    - `BackgroundTool.inlineSettleGrace` becomes a non-optional `TimeInterval`. Its default implementation reads the configured value. 0 is a host's explicit choice to background at once. `nil` is not a value. Update every conformer in Multitool and Router.
    - Extra acceptance tests: a host with a 1 s setting gets a pending envelope for `sleep 3`; a host with the default gets the inline result for `sleep 3`.

    Design:
    - Extras: `ToolMount.defaultInlineSettleGrace = 6` is the one constant. `MountSite` carries the configured grace. The runner binds it into a task-local while it reads `tool.inlineSettleGrace`, so the default implementation reads the configured value. `ToolContext` keeps the grace of its site and gives it to `mount(...)`, so inner calls get it.
    - An inner call's grace is clipped to the remaining grace of the outer run, less a reserve, so a snippet with a long inner call still settles inside the outer grace.
    - A run that settles inside the grace returns the tool's own output, or throws its own error, the same as a synchronous call. The settled envelope and `resultInstruction` go away; the staged mail is still withdrawn.
    - Router: `SessionConfiguration` gets the setting and passes it to `MountSite`; `ToolOutputCapping` loses the settled-envelope case; fixtures update.
    - Agents: the `toolHasNoInlineSettleGrace` test changes.
    - Multitool: `MultiToolConfiguration.defaultInlineSettleGrace` reads the Extras constant; inner calls mount with the configured grace; `execute` gives a snippet an object.
  timestamp: 2026-10-08T15:19:21.148914+00:00
position_column: done
position_ordinal: ffffc780
title: Background tool call that ends inside 6 s returns its result directly
---
Request from foundationmodelsacpagent-19 (SWE-bench run, django__django-14016).

Rule: each background tool call waits up to 6 s. A call that ends inside 6 s returns its own result, the same as a synchronous call. No `pending`, no `completionToken`, no `next`, no envelope with `pending: false`. Only a call that runs longer than 6 s returns the pending envelope, and its result comes back later as mail. This applies to every background tool, at the top level and inside a `runCode` snippet, and most of all to `tools.shell.execute`.

Changes:
1. FoundationModelsExtras: `BackgroundTool.inlineSettleGrace` defaults to 6 s. When the run settles inside the grace, `BackgroundToolRunner` returns the tool's own result, not an envelope. Keep `withdrawStagedEvents`.
2. Multitool: `runCode` default is the same 6 s, from one constant. An inner call of a background tool waits for the grace and gives back the result itself when the run settles.
3. `execute` gives a structured object to a snippet: `commandID`, `exitCode`, `durationMs`, `lines`, `output`. A pending result is the object `{pending: true, commandID, next}`.

Acceptance tests (through the real Router session mount):
1. Snippet `execute` of `echo hi`, `return r.exitCode` → `0`, no envelope, no mail.
2. Top-level `execute` of `echo hi` → the report, no `pending` key.
3. Snippet `execute` of `sleep 8` → `{pending: true, commandID}`; `getLines` accepts the id; one mail later.
4. `runCode` snippet that ends inside 6 s → its own value, no envelope.
5. A test that fails if a `BackgroundTool` in this package has no grace.

When done, send the commit to foundationmodelsacpagent-19.