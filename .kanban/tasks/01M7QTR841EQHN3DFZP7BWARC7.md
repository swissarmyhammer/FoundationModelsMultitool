---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m7qts98czyrp75pyhj4j5kpk
  text: 'Answer to the open question (from testudoapp-9a, 2026-11-18): keep `archivedAt`. Extras adds `SessionSummary.archivedAt: Date?` (nil when not archived) in its D204 work, and the Router sets it from the archive record and clears it at unarchive. Read it from the summary and give it as ISO 8601 text, or `null`. Do not make a time in Multitool. The app sorts the Archived section by it, newest first. If the Extras sha has no `archivedAt`, stop and ask testudoapp-9a.'
  timestamp: 2026-11-18T17:20:31.500310+00:00
- actor: claude-code
  id: 01m7qxwk05k34j1ad8w4cfrjb0
  text: |-
    Research (implement):
    - Extras pin 4c521cb has `SessionSummary.archivedAt: Date?`. `InMemorySessionDirectory` sets it from its own `now` clock at archive and clears it at unarchive. Multitool reads it; it makes no time.
    - `SessionsGraphSession` maps each time to `DateTime` (RFC 3339 text, an ISO 8601 profile), as `pinnedAt` and `lastUsedAt`. `archivedAt` uses the same shape: `summary.archivedAt.map(DateTime.init)`.
    - The note `archived` comes in `SessionSendReceipt.reason` of a `sent` receipt (Extras `archivedNote`). The tool line for `.sent` in `SessionsToolText+Messages.swift` ignored the reason. The GraphQL `SendReceipt.reason` already gives the note to a client (it copies `receipt.reason`), so the graph needs no code change for the note.
    - Not on the card, so not changed here: the `archiveSession` mutation description and the `SendReceipt.reason` description ("Why the target refused the message, or null.") still say an archived session takes no messages / only a refusal has a reason. The `archivedAdvice` of a refused receipt with reason `archived` is also stale. See the new task for these.
  timestamp: 2026-11-18T18:14:45.509545+00:00
- actor: claude-code
  id: 01m7qy5baeb729crtjpcc1kn0z
  text: |-
    ### implement — changed
    - evidence: 8 files — Sources/.../Sessions/SessionsGraphTypes.swift (`archivedAt: DateTime?` from `summary.archivedAt`), SessionsGraphSchema.swift (field `archivedAt`, the `ARCHIVED` description), SessionsToolChangeOperations.swift (`archive session` description), SessionsToolText.swift (tool description, the `notASessionID` corrective names `unarchive session`), SessionsToolText+Messages.swift (`archivedNoteSentence` on a `sent` receipt with the note `archived`), Tests/.../Goldens/sessions.graphql (re-recorded: only the `ARCHIVED` description and the `archivedAt` field change), Tests/.../SessionsGraphPageTests.swift (2 tests), Tests/.../SessionsToolMessageTests.swift (1 test). RED: the 3 new tests failed (no field `archivedAt`; no note in the answer). `swift test --filter` over 8 session suites: 183 tests passed. Full `swift test`: 3102 tests in 275 suites passed, 0 Swift warnings. SKILL.md not changed (^r0cpp1p).
    - next: review. New task ^jqqfsf for 3 stale texts outside this card: the `archiveSession` mutation description, the `SendReceipt.reason` description, and `archivedAdvice`.
  timestamp: 2026-11-18T18:19:32.558975+00:00
- actor: claude-code
  id: 01m7qy5jbj679ccr4r05y2js0n
  text: 'Correction to the step record: the new task for the 3 stale texts is ^3jqqfsf, not ^jqqfsf.'
  timestamp: 2026-11-18T18:19:39.762505+00:00
- actor: claude-code
  id: 01m7qy9bfc764swfb9fsv14bz7
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (f34de580): 0 findings (7 files reviewed; 0 confirmed, 0 refuted, 0 failed). The golden schema file and the .kanban files are not reviewed: no validator matches, or an ignore rule excludes them.
    - next: none. The task moved to done. The follow-up task ^3jqqfsf has the three old archive texts.
  timestamp: 2026-11-18T18:21:43.788967+00:00
- actor: claude-code
  id: 01m7qy9py7psjmzg0vcjpkqdpm
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — SessionsGraphTypes, SessionsGraphSchema, SessionsToolChangeOperations, SessionsToolText, SessionsToolText+Messages; golden schema; SessionsGraphPageTests, SessionsToolMessageTests; follow-up ^3jqqfsf for three old archive texts
    - test: green — swift test, 3102 passed (run in the implement step)
    - commit: f34de580
    - review: clean — 0 findings
  timestamp: 2026-11-18T18:21:55.527380+00:00
depends_on:
- 01M7QTQMJ80F89T52BZKA7BYH8
position_column: done
position_ordinal: ffffffff9780
title: archivedAt on a session, and the archive texts of the tool and the receipt note archived (D204)
---
Decision: D204 in TestudoApp/features/decisions.md (commit 9281f9c). Brief: /Users/wballard/github/swissarmyhammer/.briefs/archive/mt-brief.md, items 4 and 5.

Precondition: ^ka7byh8 (the Extras pin). OPEN QUESTION: the brief asks for `archivedAt`, but the Extras brief gives no archive time on `SessionSummary`. Before you start, find the source of the archive time in Extras and the Router on origin/main. If there is none, ask the TestudoApp session (`testudoapp-9a`) and do not invent a time.

## Work

- Add the field `archivedAt` (an ISO 8601 text, or `null`) to the `Session` type (`SessionsGraphSchema.swift`, `SessionsGraphSession`), so the Archived list of the app can sort by the newest archive first.
- Change the description of the `SessionState` value `ARCHIVED`: "The session is archived: hidden from the lists, not live. `unarchiveSession` brings it back."
- `archive session` (`SessionsToolChangeOperations.swift`): "Archive a session: stop its turn and hide it from the lists. It is not deleted: its transcript and its inbox stay, and `unarchive session` brings it back."
- The tool description (`SessionsToolText.swift`): "archive and unarchive a session".
- The `send message` receipt text: a `sent` receipt with the note `archived` says "The session is archived. The message waits in its inbox until the user unarchives and opens it."
- The corrective "An archived session has only its id" (`SessionsToolText.swift`) names the exception of `unarchive session`.
- Re-record the golden schema; the diff must only add or change the described lines.

## Tests

- [x] Graph: `sessionPage(filter: {state: ARCHIVED, includeRecorded: true})` gives the archived session with its `archivedAt`.
- [x] Graph: an unarchived session has `archivedAt: null`.
- [x] Tool: `send message` by full id to an archived session gives a receipt text with the note. #sessions #archive #graphql