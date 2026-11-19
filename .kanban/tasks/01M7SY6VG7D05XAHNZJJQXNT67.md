---
assignees:
- claude-code
depends_on:
- 01M7SY6A33T5FEKCS8245E2JWW
position_column: todo
position_ordinal: '8380'
title: The sessions skill names search sessions (D207)
---
Decision: D207 in TestudoApp/features/decisions.md (commit ba585e0). Brief: /Users/wballard/github/swissarmyhammer/.briefs/search/mt-brief.md, item 6.

Precondition: ^45e2jww (the operation and its one example row).

## Work

In `Sources/FoundationModelsMultitool/Resources/skills/sessions/SKILL.md`, in ASD-STE100 Simplified Technical English, version 1.6.0:
- Keep one example row: `{"op": "search sessions", "query": "\"retry budget\" folder:.", "limit": 10}`.
- Add the parameter list of `search sessions` (`query`, `folder`, `archived`, `limit`) in the form that `parameterList(of:in:)` of SessionsSkillTests reads.
- Add: "To find an earlier session by its content or by its meaning, use `search sessions`. Then read it with `export session` and the file tools. Do not read the transcript files."
- Add: "The search covers only the sessions of this server, not the sessions of other agents."
- Name the query tokens in one short list.
- After the push, send the commit sha to the peer sessions `foundationmodelsacpagent-9e` and `testudoapp-9a`.

## Tests

- [ ] SessionsSkillTests finds each parameter of `search sessions` in its parameter list.
- [ ] SessionsSkillTests checks the limit sentence, with a proof that the check can fail.
- [ ] SessionsSkillTests and BuiltinSkillsTests stay green. #sessions #search