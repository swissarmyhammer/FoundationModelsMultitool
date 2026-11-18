---
assignees:
- claude-code
position_column: todo
position_ordinal: 8b80
title: The sessions skill shows the message header of the Router, From the user, in title (folder) (D199)
---
Decision: D199 (f) in TestudoApp/features/decisions.md. Found by the TestudoApp integration test, 2026-11-18. ACPAgent ^zjmdtkg checks the result against the real stack.

## Current behavior

The `sessions` skill 1.1.0 (`Sources/FoundationModelsMultitool/Resources/skills/sessions/SKILL.md`, commit a5234d76) shows the header of a user message from another session as `[message from the user, in session "<title>" (<folder>), id <id>]`.

The Router (origin/main 2ece8097) writes `From the user, in <title> (<folder>)`, then a blank line, then the text. That is the D199 (f) form. The skill must follow the Router.

## Work

- Read the header code of the Router on origin/main (../FoundationModelsRouter): the header of a user message with a source session, and the header of a message from a session (title, agent, folder). Copy each form exactly.
- Change the skill text and each example to the Router forms. Write in ASD-STE100 Simplified Technical English. Change the version to 1.1.1.
- If the Router gives a public function or constant for the header and this package can import it, the skill test compares the skill examples with it. If not, the skill test checks the literal form `From the user, in ` and says in a comment where the Router writes it.
- After the push, send the commit sha to the peer sessions `foundationmodelsacpagent-9e` and `testudoapp-9a`.

## Tests

- [ ] The skill shows the header of a user message in the Router form, and not the old form.
- [ ] The skill shows the header of a message from a session in the Router form.
- [ ] SessionsSkillTests and BuiltinSkillsTests stay green. #sessions #at-sessions #bug