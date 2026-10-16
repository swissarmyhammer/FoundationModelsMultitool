---
assignees:
- claude-code
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