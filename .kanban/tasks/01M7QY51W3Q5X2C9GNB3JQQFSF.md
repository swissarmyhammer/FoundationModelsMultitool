---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m7qyk4ajqtxj3qth3bxq52xq
  text: |-
    Research and implementation notes.
    - Pins (coordinator order): `swift package update FoundationModelsExtras` moved Extras to 87d1da9 (87d1da96aad7536fbb16947b83ee11e43b8014d6). Router stays at 18bbe4daf1b705a0ec702ff532dec0ee8c059753. No other sibling moved. Package.resolved is gitignored.
    - Decision on `archivedAdvice`: Extras 87d1da9 has no refusal with the reason "archived" (the refusals are noSessionInTheFolder, noSessionHasTheTag, tooManyTargets, chainTooDeep, tooManySends; an archived target gets `sent` with the note "archived"). Thus the refusal path with the reason `archived` does not stay. `archivedAdvice` and its use in `receipts(_:)` are removed. `archivedReason` stays: it is the note of a `sent` receipt. New test `aRefusalWithTheReasonArchivedGivesNoAdvice`.
    - Other texts that said an archive is final, changed the same way: `archiveSentence` and `archivedAlready` in SessionsToolText+Changes.swift (they now say that a message waits in the inbox and that `unarchive session` / `unarchiveSession` brings the session back; `startSessionVerb` became `unarchiveSessionVerb`, no other caller); the `SendOutcome.REFUSED` description and the `SessionsGraphOutcome.refused` doc ("A loop guard or no match refused the message."); the `SessionsGraphReceipt.reason` doc; the MT-7 TODO in SessionsToolChangeOperations.swift. SKILL.md not changed (^r0cpp1p).
    - Golden `sessions.graphql` re-recorded with GRAPHQL_GOLDEN_RECORD=1: 3 descriptions changed (REFUSED, SendReceipt.reason, archiveSession), nothing else.
    - The RED run was not done separately, because the order allows one test run. The three new tests ran in the full suite.

    ### implement — changed
    - evidence: Sources/FoundationModelsMultitool/Capabilities/Sessions/SessionsGraphMutations.swift, SessionsGraphTypes.swift, SessionsToolChangeOperations.swift, SessionsToolText+Changes.swift, SessionsToolText+Messages.swift; Tests/FoundationModelsMultitoolTests/SessionsToolChangeTests.swift (2 new tests), SessionsToolMessageTests.swift (1 new test), Goldens/sessions.graphql. `GRAPHQL_GOLDEN_RECORD=1 swift test --filter SessionsGraphQueryTests/theSchemaMatchesTheGoldenFile`: 1 test passed. Full `swift test` (one time, in place of the filtered run): 3109 tests in 276 suites passed, 0 issues, 0 Swift warnings, exit 0. Extras 87d1da9, Router 18bbe4d.
    - next: /review
  timestamp: 2026-11-18T18:27:04.146752+00:00
position_column: doing
position_ordinal: '80'
title: Archive texts of the archiveSession mutation and the SendReceipt reason (D204)
---
Found during ^7bwarc7. Three texts still say that an archived session takes no messages. D204 says an archive is not final, and a message to an archived session waits in its inbox (receipt `sent`, note `archived`).

## Work

- `SessionsGraphMutations.swift`, the `archiveSession` mutation description: "Archives a session: stops its turn and ends its work. It takes no more messages, and its transcript stays." Change it to agree with the `archive session` operation text (hide it from the lists, not deleted, `unarchiveSession` brings it back).
- `SessionsGraphMutations.swift`, the `SendReceipt.reason` field description: "Why the target refused the message, or null." A `sent` receipt now carries the note `archived` in this field. Name the note.
- `SessionsToolText+Messages.swift`, `archivedAdvice`: "An archived session takes no messages." The directory no longer refuses an archived target. Decide if the refusal path with the reason `archived` stays, and correct or remove the advice.
- Re-record the golden schema; the diff must only change these lines.

## Tests

- [x] The golden schema test passes with the new descriptions.
- [x] A test covers the decision about `archivedAdvice`. #sessions #archive #graphql