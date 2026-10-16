---
assignees:
- claude-code
depends_on:
- 01M53FG8K2C3T24RJWRNF9DKS3
position_column: todo
position_ordinal: '8680'
title: 'Group D (d): correct the elicitation text in README and docs/SECURITY.md'
---
Elicitation fixes from the 2026-10-16 check (elicitation-plan.md section 10), group D (d).

README.md and docs/SECURITY.md must describe:
- the { action, content, reason } result,
- the headless MCP cancel,
- the progress-token link of a server question to its call.

docs/SECURITY.md about line 62 names "Router's own ElicitationRequest", but the type is in FoundationModelsExtras. Correct it.

If a test reads these files (HardeningTests reads the README list of globals), keep it green. One full run. #elicitation-fixes