---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m7t1fab3ckve495xda99w7vy
  text: |-
    Research: the operation `SearchSessions` (SessionsToolSearchOperation.swift) has the parameters `query` (necessary), `folder`, `archived` and `limit` (1 to 50, default 20). The tokens come from the doc of `SessionSearchQuery`: phrase, `-word`, `from:<kind>` (default: each kind but `thought`), `after:`/`before:` YYYY-MM-DD, `@<session>`, `#<tag>`, `agent:`, `folder:` (`.` is the caller folder), `is:archived`. The tool limit line (`SessionsToolText.searchLimitSentence`) has other words than the skill sentence of the card, so the skill test checks the sentence of the card.

    Implementation: SKILL.md is 1.6.0. It has the find rule, the limit sentence, the parameter list of `search sessions`, one list of the query tokens, one line about the answer, and `tools.sessions.searchSessions` in the code-mode line. The one example row stays. In SessionsSkillTests, the two tests for export and fork are now one parameterized test over `listedOperations` (export, fork, search) that calls `unnamedParameters(of:)`. A new helper `tellsTheSearchLimit(_:)` has a proof test on a small text with no limit sentence, and a test on the skill.

    Note: the instruction was to run the tests one time, so I did not do a separate RED run.

    The last item of the card (send the sha to the peer sessions after the push) is for the commit step: I did not commit.
  timestamp: 2026-11-19T13:55:53.827682+00:00
- actor: claude-code
  id: 01m7t1fcg9hx3g02byg1karx4k
  text: |-
    ### implement — changed
    - evidence: 2 files — Sources/FoundationModelsMultitool/Resources/skills/sessions/SKILL.md, Tests/FoundationModelsMultitoolTests/SessionsSkillTests.swift; `swift test --filter "SessionsSkillTests|BuiltinSkillsTests"`: 24 tests in 2 suites passed, 0 failures, 0 warnings
    - next: review; after the push, send the commit sha to `foundationmodelsacpagent-9e` and `testudoapp-9a`
  timestamp: 2026-11-19T13:55:56.041699+00:00
depends_on:
- 01M7SY6A33T5FEKCS8245E2JWW
position_column: doing
position_ordinal: '80'
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

- [x] SessionsSkillTests finds each parameter of `search sessions` in its parameter list.
- [x] SessionsSkillTests checks the limit sentence, with a proof that the check can fail.
- [x] SessionsSkillTests and BuiltinSkillsTests stay green. #sessions #search