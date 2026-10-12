---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: Name the pending inner calls of a nested tools.runCode in the outer runCode result
---
## Problem

Task ^qg52whq added `PendingInnerCalls`. The runCode result now names each inner call that is still pending when the snippet ends. The notice is only on a run at depth 0. A nested `tools.runCode` run gets no notice, because a snippet reads its text (`makeNestedRunCodeHostFunction` decodes it).

Thus, when a nested snippet starts a long `tools.shell.execute`, does not return the pending object, and ends, the outer runCode result does not name that call. The model can run the call again.

## Work

- Let a nested run report its pending inner calls to the record of the outer run (for example, pass the outer `PendingInnerCalls` to the nested `MultiTool`), so the outer result names them.
- Keep the nested result text a plain value that the snippet can decode.

## Acceptance

- [ ] A test: an outer snippet calls `tools.runCode` with a nested snippet that starts a long execute and does not return it. The outer result names the pending call (path, tool, op, commandID).
- [ ] Tests pass.

#bug