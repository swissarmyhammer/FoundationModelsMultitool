---
assignees:
- claude-code
depends_on:
- 01M7QTR1ZHE0M58T1BPNT5HH30
- 01M7QTR841EQHN3DFZP7BWARC7
position_column: todo
position_ordinal: '8380'
title: The sessions skill tells that an archive is not final, and names unarchive session (D204)
---
Decision: D204 in TestudoApp/features/decisions.md (commit 9281f9c). Brief: /Users/wballard/github/swissarmyhammer/.briefs/archive/mt-brief.md, item 6.

Precondition: ^nt5hh30 (the operation) and ^7bwarc7 (the texts and the receipt note). SessionsSkillTests requires an example for each operation of the tool, so this task must land in the same push as ^nt5hh30 or right after it.

## Work

In `Sources/FoundationModelsMultitool/Resources/skills/sessions/SKILL.md`, in ASD-STE100 Simplified Technical English, version 1.3.0:
- The description: add "unarchive".
- "An archived session matches only its id, except in `unarchive session`, where the short id and the slug match archived sessions."
- "A message to an archived session waits in its inbox (receipt `sent`, note `archived`). The session does not start a turn. Tell the user, or start a new session for the work."
- A row in the table: `| Unarchive a session | {"op": "unarchive session", "id": "@build-fix"} |`.
- "Archive a session only when the user asks, or when you started it and its work is done. An archive is not final: `unarchive session` brings the session back."
- Remove each old text that says that an archive is final or that an archived session takes no messages.
- After the push, send the commit sha to the peer session `testudoapp-9a`.

## Tests

- [ ] SessionsSkillTests finds `unarchive session` and its example.
- [ ] The skill names the note `archived` of a `sent` receipt.
- [ ] SessionsSkillTests and BuiltinSkillsTests stay green. #sessions #archive