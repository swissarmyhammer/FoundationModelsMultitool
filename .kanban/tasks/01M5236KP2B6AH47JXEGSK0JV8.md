---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m524q75xd1smq0f4bxtttsjp
  text: 'Owner note (2026-10-16): Extras makes ToolContext.holdingRunToken public. It groups the SYNCHRONOUS inner calls of one run (also nested calls). An inner tools.* call that is mounted as BACKGROUND is a run of its own and has its own token. When this card starts: check how runCode mounts the tools.* calls that reach MCP servers (synchronous or background), and record the result here. Start only after the owner says that Extras has pushed, and after phase 5.'
  timestamp: 2026-10-16T10:39:28.445533+00:00
position_column: todo
position_ordinal: '8880'
title: Link a server elicitation to the one holding run of two inner runCode calls
---
Found in ^djgymyd. MCPServer+Elicitation.swift step 2 (one run) compares the ToolContext of each call in flight by completionToken. Each inner tools.* call of one runCode snippet is a mounted run with its own completionToken (RunBinding.invoke). Thus two inner MCP calls of one snippet on one server, with no progressToken echo from the server, get cancel with the reason "the question cannot be linked to one tool call". Both calls are held by the same run (the runCode run), and a question through either context links to that run.

Precondition (other repo): FoundationModelsExtras must make the holding run token of a ToolContext public (today `ToolContext.holdingRunToken` is internal at e65287a). Send that card text to the peer session of FoundationModelsExtras first.

Do, after the precondition:
- Compare by the holding run token in contextOfTheOneRunInFlight().
- A fixed-order test: one runCode snippet calls a held MCP tool and an eliciting MCP tool (no token echo) at the same time; the question reaches the runCode run. It fails on the old code as a check.

#elicitation-phase-3