---
assignees:
- claude-code
position_column: todo
position_ordinal: '9680'
title: End a host-handler URL accept that returns after the connect generation moved
---
Found during ^fcvjb8j.

In resolve(...) of MCPServer+Elicitation.swift, the host elicitationHandler can be called while the generation of its client is current, and return accept after a disconnect or a new connect moved the generation. endHeldHostElicitations() already ran at that time, thus awaitHostCompletion(of:) then holds the flow in pendingHostElicitations under the new generation. The completion can come only on the old transport, which is closed. The flow then stays held until the next disconnect or connect, and the teardown of the old client waits on the handler.

Work:
- After the handler returns accept for a URL question, compare the generation of the question with connectGeneration. When they are not equal, answer cancel with connectionEndedReason in _meta.reason and do not hold the flow.
- Start with a fixed-order RED test (rule T1): a handler that waits on a gate, a wait for the handler call, a disconnect, then the gate opens. Each wait also ends on the failure event. #elicitation-fixes