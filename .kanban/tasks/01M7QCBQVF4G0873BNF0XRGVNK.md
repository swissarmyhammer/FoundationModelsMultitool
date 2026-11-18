---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m7qea4nxgh6ybzpzx2y2tc75
  text: 'Extras (2026-11-18): a message to a recorded session now gives the receipt `sent` (it goes to the inbox, with no turn). Thus the receipt words are `delivered`, `queued`, `sent`, `refused` and `started`. The skill text and its test must name `sent` too, and TestudoApp must know the word.'
  timestamp: 2026-11-18T13:42:32.381959+00:00
- actor: claude-code
  id: 01m7qkvxkmz99mzwrcvgyzbv10
  text: |-
    Research (implement step):
    - The draft skill is mostly true for main. Gaps: the receipt word `sent` is not named; the forms `<id>` and `<short id>` without @, the aliases `@agent:/path` and the folder path are not named; the rewrite line of an alias is not named; "add includeRecorded" in the table is not a full `{"op": ...}` example.
    - The receipt words come from the code: `SessionsGraphOutcome` (SessionsGraphTypes.swift) is `CaseIterable`, and its raw values in lower case are `delivered`, `queued`, `started`, `refused`, `sent`. The tool line words (SessionsToolText+Messages.swift `line(for:)`) are "Delivered to", "Queued for", "Started", "Refused", "Sent to". `SessionSendReceipt.Outcome` of Extras is not CaseIterable, so the test reads the GraphQL enum.
    - Code-mode verbs: `OperationVerbTool.verbName(for: opString)` over `SessionsTool.operationDescriptors`. Parameter names and aliases: `OperationParameterDescriptor.name` and `.aliases`.
    - `SessionReference.resolve` (Extras): an archived session never matches a reference, not even by its full id.
  timestamp: 2026-11-18T15:19:37.844145+00:00
- actor: claude-code
  id: 01m7qm16mjpwjnrxgge93msc1t
  text: |-
    ### implement — changed
    - evidence: 3 files. SKILL.md (names `sent`, `<id>`/`<short id>` without @, the aliases `@agent:/path` and a folder path with the `Rewrite:` line, AMBIGUOUS_REFERENCE, the `id` forms of each session operation, a full `includeRecorded` example, version 1.1.0); new Tests/FoundationModelsMultitoolTests/SessionsSkillTests.swift (6 tests, 12 cases; receipt words from `SessionsGraphOutcome.allCases`, verbs from `OperationVerbTool.verbName(for:)`); BuiltinSkillsTests.swift (`sessionsSkillFile` is internal, so the new suite reads the same file). `swift build` ok. `swift test --filter "SessionsSkillTests|BuiltinSkillsTests"`: first run 1 issue (the skill wrote `refused: <reason>` but not `refused` alone), skill text corrected, second run 10 tests in 2 suites pass. Full `swift test` one time: 3041 tests in 272 suites pass.
    - note: the skill test checks each word in backticks, for example `` `sent` ``.
    - next: /review
  timestamp: 2026-11-18T15:22:30.930147+00:00
depends_on:
- 01M7QCD0WVWRMD9QCBVE46CB97
- 01M7NQM8VTYF6G2ZW1QGRJJ9R4
- 01M7NQMS04V5B1WKXMY6XZNEGM
- 01M7QCBB4ARPTB8SNGHZKEWPEX
position_column: doing
position_ordinal: '80'
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

- [x] Each `{"op": "..."}` example of the skill decodes to an operation of `SessionsTool`, and each key of the example is a parameter or an alias of that operation.
- [x] Each code-mode verb that the skill names (for example `tools.sessions.sendMessage`, `tools.sessions.listSessions`) is a verb of the tool.
- [x] The skill names each of the forms `@<id>`, `@<short id>` and `@<slug>`, and each receipt word of the tool.
- [x] The existing session tool tests stay green. #sessions #at-sessions