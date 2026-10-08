---
assignees:
- claude-code
depends_on:
- 01M4E1XR9RGN1BNPYHWDKT9H63
- 01M4E2HPENAVR0VT8MWC73RK0S
position_column: todo
position_ordinal: '8480'
title: Document the environment capability in README.md
---
## What
Document the environment capability in `README.md`.

Decisions from the user (2026-10-08):
- Do NOT change `docs/SECURITY.md`. This task changes only `README.md`.
- Do NOT add a secret warning. The model can already read each variable with a shell command (`tools.shell.*`), thus `tools.environment.variables` is not a new risk. Do not change the key sentence of `### Web`.

`README.md`:
- Add a `### Environment` section under `## Capabilities`, after `### Git` and before `### Injected globals`. Use the same form as `### Git`. The section must:
  - Name the builder short form `withEnvironment()`, and say that the capability is off by default.
  - Name each verb: `tools.environment.variables`, `tools.environment.os`, `tools.environment.now`, with one short example snippet in JavaScript, for example:
    ```js
    const { date, weekday, timeZone } = await tools.environment.now({});
    const { name, version } = await tools.environment.os({});
    const { variables } = await tools.environment.variables({ prefix: "LANG" });
    ```
  - Say that the capability is read-only.
- In the `## Capabilities` introduction, change "Five capabilities ship with the package" to six, and add **environment** to the list.

Write the new text in ASD-STE100 Simplified Technical English.

## Acceptance Criteria
- [ ] The `## Capabilities` section of `README.md` names `withEnvironment()`, each of the three verbs, and `read-only`.
- [ ] The `## Capabilities` introduction says six capabilities and names environment.
- [ ] `docs/SECURITY.md` and the `### Web` section are not changed.

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/EnvironmentDocumentationTests.swift` — model it on `GitDocumentationTests.swift`. Each test reads only its own section: assert each required text of the `### Environment` section and the count "six" in the introduction.
- [ ] Make sure that no other documentation test (for example `ExamplesTests.swift` or `HelpDocsTests.swift`) fails because of the new text.
- [ ] Run `swift test` — all tests pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #environment