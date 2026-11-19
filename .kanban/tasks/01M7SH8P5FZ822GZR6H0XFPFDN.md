---
assignees:
- claude-code
depends_on:
- 01M7SH8E01E70SDH3YTVTMGQYK
position_column: todo
position_ordinal: '8180'
title: The sessions skill names the recap of a session (D206)
---
Decision: D206 in TestudoApp/features/decisions.md (commit da60a90). Brief: /Users/wballard/github/swissarmyhammer/.briefs/recap/mt-brief.md, item 5.

Precondition: ^vtmgqyk (the recap in `check session` and `list sessions`).

## Work

In `Sources/FoundationModelsMultitool/Resources/skills/sessions/SKILL.md`, in ASD-STE100 Simplified Technical English, version 1.5.0:
- Add one sentence: the recap tells what a session did and where it stands now. Read it with `check session` before you send a message to a session that you do not know.
- Do not tell the agent to write a recap: no operation writes one (D206 (h)).
- After the push, send the commit sha to the peer session `testudoapp-9a`.

## Tests

- [ ] SessionsSkillTests checks that the skill names the recap.
- [ ] SessionsSkillTests and BuiltinSkillsTests stay green. #sessions #recap