---
assignees:
- claude-code
depends_on:
- 01M7QCD0WVWRMD9QCBVE46CB97
- 01M7NQM8VTYF6G2ZW1QGRJJ9R4
- 01M7NQMS04V5B1WKXMY6XZNEGM
- 01M7QCBB4ARPTB8SNGHZKEWPEX
position_column: todo
position_ordinal: '8580'
title: The sessions skill text follows the D199 address forms, with a test against the tool (D200)
---
Decision: D200 in TestudoApp/features/decisions.md, after D199. Brief: /Users/wballard/github/swissarmyhammer/.briefs/at-sessions/mt-brief-sessions-skill.md, item 4 and the tests.

^e46cb97 ships the resource `skills/sessions/SKILL.md` (the draft text) and `BuiltinSkills.directory`. This task edits that text for the new address forms and adds the test of the skill against the tool.

Precondition: the skill names the forms of D199 and the short id and the slug in `list sessions`. Thus it depends on ^e46cb97 (resource), ^grjj9r4 (short id, slug), ^6xznegm (address reader) and ^zkewpex (the `id` of each change operation takes a short id and `@<slug>`).

The pattern to copy: FoundationModelsKanban `Tests/FoundationModelsKanbanTests/KanbanSkillTests.swift:9-40` checks the frontmatter keys and runs each example against the tool.

## Work

- Edit `Sources/FoundationModelsMultitool/Resources/skills/sessions/SKILL.md` as the tool requires, in ASD-STE100 Simplified Technical English. Keep it short: the agent reads it at each session start.
- The receipt words `delivered`, `queued`, `refused` and `started` are the same in the tool (`SessionsToolText+Messages.swift:120-134`), in the endpoint and in the skill.

## Tests

- [ ] Each `{"op": "..."}` example of the skill decodes to an operation of `SessionsTool`, and each key of the example is a parameter or an alias of that operation.
- [ ] Each code-mode verb that the skill names (for example `tools.sessions.sendMessage`, `tools.sessions.listSessions`) is a verb of the tool.
- [ ] The skill names each of the forms `@<id>`, `@<short id>` and `@<slug>`, and each receipt word of the tool.
- [ ] The existing session tool tests stay green. #sessions #at-sessions #blocked-external