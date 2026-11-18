---
assignees:
- claude-code
position_column: todo
position_ordinal: '8680'
title: Archive texts of the archiveSession mutation and the SendReceipt reason (D204)
---
Found during ^7bwarc7. Three texts still say that an archived session takes no messages. D204 says an archive is not final, and a message to an archived session waits in its inbox (receipt `sent`, note `archived`).

## Work

- `SessionsGraphMutations.swift`, the `archiveSession` mutation description: "Archives a session: stops its turn and ends its work. It takes no more messages, and its transcript stays." Change it to agree with the `archive session` operation text (hide it from the lists, not deleted, `unarchiveSession` brings it back).
- `SessionsGraphMutations.swift`, the `SendReceipt.reason` field description: "Why the target refused the message, or null." A `sent` receipt now carries the note `archived` in this field. Name the note.
- `SessionsToolText+Messages.swift`, `archivedAdvice`: "An archived session takes no messages." The directory no longer refuses an archived target. Decide if the refusal path with the reason `archived` stays, and correct or remove the advice.
- Re-record the golden schema; the diff must only change these lines.

## Tests

- [ ] The golden schema test passes with the new descriptions.
- [ ] A test covers the decision about `archivedAdvice`. #sessions #archive #graphql