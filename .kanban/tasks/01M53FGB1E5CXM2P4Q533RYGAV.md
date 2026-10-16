---
assignees:
- claude-code
depends_on:
- 01M53FG8K2C3T24RJWRNF9DKS3
position_column: todo
position_ordinal: '8580'
title: 'Group D (c): make the default userPresence of MCPServer safe, or make the value required'
---
Elicitation fixes from the 2026-10-16 check (elicitation-plan.md section 10), group D (c).

The default userPresence of MCPServer is .interactive (MCPServer.swift about line 436). A headless host that forgets the value advertises elicitation.

Two choices: make the default safe (headless), or make the value required. This changes public API.

STOP before the change: first find which callers and tests use the default, and send the facts and a recommendation to the owner's coordinating session (swissarmyhammer-96) in plain text. Do the change only after the owner chooses. Record the choice here.

The fix starts with a fixed-order test that fails before the fix (RED), then passes (GREEN). One full run. #elicitation-fixes