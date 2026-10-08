---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4ekbscs1335gj8c512h328g
  text: 'Research done. The capability has three verbs: `variables` (args `name?` or `prefix?`, not both; result `variables` as name/value pairs in name order, plus `correction`), `os` (no args; result `name`, `version`, `build`, `architecture`, `hostName`, `userName`, `homeDirectory`, `processorCount`, `physicalMemoryBytes`, `locale`), and `now` (arg `timeZone?` as an IANA identifier; result `iso8601`, `utc`, `date`, `time`, `weekday`, `timeZone`, `utcOffset`, `epochSeconds`, plus `correction`). An unset name, name with prefix, and an unknown time zone come back as a `correction`, not an error. Each verb reads the live value at each call. `withEnvironment()` takes no argument and does not throw; a second call fails at `buildRegistry()`. ExamplesTests scans README.md for the phrases " wait tool" and removed clock phrases; the new text must not hold them. The user decided: no test that pins README wording, thus the `EnvironmentDocumentationTests.swift` item is skipped.'
  timestamp: 2026-10-08T20:30:33.881739+00:00
- actor: claude-code
  id: 01m4ekgp18p4k0mg0n3zs4fyw5
  text: |-
    ### implement — changed
    - evidence: README.md only (a new `### Environment` section between `### Git` and `### Injected globals`, and the `## Capabilities` introduction now says six and names environment). `swift build --build-tests` exit 0 (one SwiftPM note "missing creator for mutated node" about the dependency product mlx-swift_Cmlx.bundle; it is not a compiler warning and is not from this change). `swift test`: 2321 tests in 203 suites passed, 0 failures.
    - skipped: the `EnvironmentDocumentationTests.swift` item, by the decision of the user (no test that pins or bans README wording). docs/SECURITY.md and `### Web` are not changed.
    - next: /review
  timestamp: 2026-10-08T20:33:14.280737+00:00
- actor: claude-code
  id: 01m4ekvaj4vrb3mt33p1wx44ew
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (c240c90). Counts: findings 0, confirmed 0, refuted 0. The engine reviewed 0 files. No validator matches README.md. An ignore rule (.reviewignore) excludes the 4 .kanban/ files.
    - next: none. The task is in done.
  timestamp: 2026-10-08T20:39:02.980550+00:00
- actor: claude-code
  id: 01m4ekvr1nhkc9t3mhprcvy0zc
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — README.md; the wording-test item is removed by the user decision of 2026-10-08
    - test: green — swift test, 2321 passed
    - commit: c240c90
    - review: clean — 0 findings (no validator applies to README.md); task in done
  timestamp: 2026-10-08T20:39:16.789467+00:00
depends_on:
- 01M4E1XR9RGN1BNPYHWDKT9H63
- 01M4E2HPENAVR0VT8MWC73RK0S
position_column: done
position_ordinal: ffffcb80
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
- [x] The `## Capabilities` section of `README.md` names `withEnvironment()`, each of the three verbs, and `read-only`.
- [x] The `## Capabilities` introduction says six capabilities and names environment.
- [x] `docs/SECURITY.md` and the `### Web` section are not changed.

## Tests
- Removed (user decision of 2026-10-08): no test that pins or bans README wording. `EnvironmentDocumentationTests.swift` is not written.
  - SKIPPED by the decision of the user (2026-10-08): do not add a test that pins or bans README wording.
- [x] Make sure that no other documentation test (for example `ExamplesTests.swift` or `HelpDocsTests.swift`) fails because of the new text.
- [x] Run `swift test` — all tests pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #environment