---
assignees:
- claude-code
depends_on:
- 01M7TY6PWAXJH82MDJ5ET3QN9R
- 01M7TXYE3K8Q83PZYMS65F1NPD
position_column: todo
position_ordinal: '8580'
title: The sessions skill names list imports and import session (D209)
---
Decision: D209 in TestudoApp/features/decisions.md (commit 56a8a59). Brief: /Users/wballard/github/swissarmyhammer/.briefs/import/mt-brief.md, item 6.

Precondition: ^et3qn9r (the operations and their example rows) and ^65f1npd (the share skill text, 1.7.0; build on it).

## Work

In `Sources/FoundationModelsMultitool/Resources/skills/sessions/SKILL.md`, in ASD-STE100 Simplified Technical English, version 1.8.0:
- Keep one example row for each of `list imports` and `import session`, and their parameter lists in the form that `parameterList(of:in:)` reads.
- Add: "To continue a session of Claude Code or Codex, use `list imports` and then `import session`. The import copies the session; it does not change the source. Do not read the files of other agents."
- Say that each import makes a new session, also for a source that was imported before.
- Name `listImports` and `importSession` in the code-mode line.
- After the push, send the commit sha to `foundationmodelsacpagent-9e` and `testudoapp-9a`.

## Tests

- [ ] SessionsSkillTests finds each parameter of the two operations (reuse the parameter test with arguments).
- [ ] SessionsSkillTests and BuiltinSkillsTests stay green. #sessions #import