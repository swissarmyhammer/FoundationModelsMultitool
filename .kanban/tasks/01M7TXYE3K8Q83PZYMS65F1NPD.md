---
assignees:
- claude-code
depends_on:
- 01M7TXXYXSTM71VFGJAY8M7YVR
position_column: todo
position_ordinal: '8280'
title: The sessions skill names share session, update share and stop sharing (D208)
---
Decision: D208 in TestudoApp/features/decisions.md (commit d803f1a). Brief: /Users/wballard/github/swissarmyhammer/.briefs/share/mt-brief.md, item 6.

Precondition: ^y8m7yvr (the operations and their example rows).

## Work

In `Sources/FoundationModelsMultitool/Resources/skills/sessions/SKILL.md`, in ASD-STE100 Simplified Technical English, version 1.7.0:
- Keep one example row for each of `share session`, `update share` and `stop sharing`.
- The parameter lists, in the form that `parameterList(of:in:)` of SessionsSkillTests reads.
- When to share: only when the user asks. The link gives the transcript to other people; with `anyoneWithLink` anyone with the link can read it. `keepUpdated` keeps the shared copy current.
- Name the three operations in the code-mode line.
- After the push, send the commit sha to `foundationmodelsacpagent-9e` and `testudoapp-9a`.

## Tests

- [ ] SessionsSkillTests finds each parameter of the three operations in its parameter list (reuse the parameter test with arguments).
- [ ] SessionsSkillTests and BuiltinSkillsTests stay green. #sessions #share