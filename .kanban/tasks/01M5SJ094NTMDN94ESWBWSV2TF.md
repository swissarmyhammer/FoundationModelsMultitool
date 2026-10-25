---
assignees:
- claude-code
position_column: done
position_ordinal: ffffffe480
title: standbyAnswer with no turns (waits on Extras pendingWorkInstruction sha)
---
MultiTool+NoOpSnippet.swift:61 `standbyAnswer` ends with "…that message starts you working again. End your answer now: write no text and call no tool." Model cannot produce empty output (noqueue24 django__django-14672 child …Y48T15: 122 no-tool snippets, then `return "stop"`/"halt"/"end").

New text (no turns; take wording from the Extras function that takes the list of open calls):
> "Nothing ran: this snippet calls no tool. Still running in the background: <each open call: short description plus completion token>. Their results will arrive in this conversation as messages. If you have no other work, post your status as plain text: `Waiting on <…>`."

Blocked: start when the ACP agent session forwards the Extras sha. Failing test first. #blocked