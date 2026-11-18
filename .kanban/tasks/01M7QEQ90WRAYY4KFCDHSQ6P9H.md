---
assignees:
- claude-code
depends_on:
- 01M7QEPKFZT5MNVR9PHC4PRBTK
- 01M7QCBQVF4G0873BNF0XRGVNK
position_column: todo
position_ordinal: '8880'
title: The sessions skill names export session and its parameters (D202)
---
Decision: D202 in TestudoApp/features/decisions.md (commit 40450ab). Brief: /Users/wballard/github/swissarmyhammer/.briefs/export-markdown/mt-brief.md, item 4.

Precondition: ^c4prbtk (the operation) and ^0xrgvnk (the skill test against the tool).

## Work

- In `Sources/FoundationModelsMultitool/Resources/skills/sessions/SKILL.md`, part 4 (the management of sessions), add `export session` and its parameters `id`, `format`, `thoughts`, `path` and `replace`.
- Add one line: "To give the user a session as a file, use `export session`. It writes `<slug>.md` in the session folder."
- Write in ASD-STE100 Simplified Technical English, and keep the text short.
- After the push, send the commit sha to the peer sessions `foundationmodelsacpagent-9e` and `testudoapp-9a`.

## Tests

- [ ] The skill test of ^0xrgvnk finds `export session` and each of its parameters.
- [ ] The existing tests stay green. #sessions #export-markdown