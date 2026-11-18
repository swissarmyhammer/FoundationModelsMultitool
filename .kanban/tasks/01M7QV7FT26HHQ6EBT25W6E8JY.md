---
assignees:
- claude-code
depends_on:
- 01M7QV76HYSCM6H586BYWRZETV
position_column: todo
position_ordinal: '8580'
title: The sessions skill names fork session (D205)
---
Decision: D205 in TestudoApp/features/decisions.md (commit 483664d). Brief: /Users/wballard/github/swissarmyhammer/.briefs/fork/mt-brief.md, item 4.

Precondition: ^ywrzetv (the operation). SessionsSkillTests requires an example for each operation of the tool, so this task must land in the same push as ^ywrzetv or right after it. If the archive skill task ^r0cpp1p lands first, build on its version.

## Work

In `Sources/FoundationModelsMultitool/Resources/skills/sessions/SKILL.md`, in ASD-STE100 Simplified Technical English, with a new minor version:
- Add one row to the table of examples: `{"op": "fork session", "message": "try the other approach"}`.
- Add one sentence: a fork is a session with a copy of the history up to the call. Use it to try a second way or to ask a side question. The fork does not report back on its own, so ask it to send a message when it must.
- Name `forkSession` in the code-mode line.
- After the push, send the commit sha to the peer sessions `foundationmodelsacpagent-9e` and `testudoapp-9a`.

## Tests

- [ ] SessionsSkillTests finds `fork session`, its example and each of its parameters.
- [ ] SessionsSkillTests and BuiltinSkillsTests stay green. #sessions #fork