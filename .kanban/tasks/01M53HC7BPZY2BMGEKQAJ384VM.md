---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m53hfzb421c6tmy67kv0d9ev
  text: |-
    ### decision — owner approved the Extras API (2026-10-16)
    - The owner approved a public ToolContext.endElicitation(_:with:) in FoundationModelsExtras, as this card describes: decline or cancel only, holding run only, forwards to RunPlane.endElicitation(_:with:). The owner sent the Extras card to the Extras session.
    - Do not use ToolContext.cancel(completionToken:): it cancels the whole run and gives the wrong reason.
    - Start this card only after the owner says that Extras is pushed. Then move Extras to that revision, write the RED test, then the fix.
  timestamp: 2026-10-16T23:41:56.964407+00:00
position_column: todo
position_ordinal: '8880'
title: 'Group A (b): end the context URL flow of an old connect generation on a disconnect'
---
Split from ^zjdtdfj (group A). Elicitation fixes from the 2026-10-16 check (elicitation-plan.md section 10).

A completion from an old connect generation is dropped (MCPServer.swift about line 386). Thus the context URL flow of that generation can never complete. End it on disconnect() and on each new connect, with cancel and connectionEndedReason ("the connection to the MCP server ended before the URL flow completed").

BLOCKED (precondition, other repo): FoundationModelsExtras 7a40759 has no public way for MCPServer to end an open question of a ToolContext with a cancel and a reason. ToolContext has only elicit(_:) and complete(elicitationId:) (complete resumes with an accept). ToolContext.runPlane is internal, thus RunPlane.endElicitation(_:with:) cannot be reached. A run that settles does not end its open questions.

Proposed Extras card (waits for the owner's decision): public `ToolContext.endElicitation(_ elicitationId: ULID, with response: ElicitationResponse) async -> Bool`. It accepts a decline or a cancel only. It ends the question only when the question links to the holding run of the context, as complete(elicitationId:) does. It forwards to RunPlane.endElicitation(_:with:).
Other choice: ToolContext.cancel(completionToken: holdingRunToken) is available now, but it cancels the whole run and gives RunPlane.runCancelledReason, not the connection reason.

After the decision: a fixed-order RED test (rule T1: no wait that can hang), then the fix, then one full run. #elicitation-fixes