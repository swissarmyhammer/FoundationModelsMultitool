---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m7qts98czyrp75pyhj4j5kpk
  text: 'Answer to the open question (from testudoapp-9a, 2026-11-18): keep `archivedAt`. Extras adds `SessionSummary.archivedAt: Date?` (nil when not archived) in its D204 work, and the Router sets it from the archive record and clears it at unarchive. Read it from the summary and give it as ISO 8601 text, or `null`. Do not make a time in Multitool. The app sorts the Archived section by it, newest first. If the Extras sha has no `archivedAt`, stop and ask testudoapp-9a.'
  timestamp: 2026-11-18T17:20:31.500310+00:00
depends_on:
- 01M7QTQMJ80F89T52BZKA7BYH8
position_column: todo
position_ordinal: '8280'
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

- [ ] Graph: `sessionPage(filter: {state: ARCHIVED, includeRecorded: true})` gives the archived session with its `archivedAt`.
- [ ] Graph: an unarchived session has `archivedAt: null`.
- [ ] Tool: `send message` by full id to an archived session gives a receipt text with the note. #sessions #archive #graphql