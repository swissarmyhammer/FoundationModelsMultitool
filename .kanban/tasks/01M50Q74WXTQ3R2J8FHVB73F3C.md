---
assignees:
- claude-code
position_column: done
position_ordinal: fffff680
title: 'Elicitation phase 3: end a bound URL flow on the run plane at notifications/elicitation/complete'
---
Precondition: an Extras card that adds a run plane completion event (RunPlane.complete through a new Extras API). Do not start before it is on Extras main.

Now: on `notifications/elicitation/complete` for a flow that a bound ToolContext answered, MCPServer+Connection.swift:574 calls MCPServer.complete. That call ignores it, and records the debug record mcpElicitationCompletionIgnored.

Do:
- Keep the map from the MCP wire elicitation id to the Extras elicitationId of that question.
- On the completion notification, end the flow on the run plane through the new Extras API. Thus the URL "waiting" state of the client ends at the real end of the flow.
- Remove the map entry when the flow ends, also on cancel, decline and session close.

Done when: a fixed-order test fails on the old code as a check (for example, the run plane gets no completion event) and passes with the change; one full run passes. #elicitation-phase-3