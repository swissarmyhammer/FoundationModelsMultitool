---
assignees:
- claude-code
depends_on:
- 01M7QTQMJ80F89T52BZKA7BYH8
position_column: todo
position_ordinal: '8180'
title: unarchive session and the unarchiveSession mutation, with NOT_ARCHIVED (D204)
---
Decision: D204 in TestudoApp/features/decisions.md (commit 9281f9c). Brief: /Users/wballard/github/swissarmyhammer/.briefs/archive/mt-brief.md, items 1 and 2.

Precondition: ^ka7byh8 (the Extras pin with `SessionDirectory.unarchive(_:by:)` and `SessionDirectoryEvent.unarchived`).

## Work

- Add `@Operation(verb: "unarchive", noun: "session")` (`unarchiveSession` in code mode) next to `ArchiveSession` (`Capabilities/Sessions/SessionsToolChangeOperations.swift`). One `id`. Description: "Unarchive a session: show it again in the lists. It stays a recorded session until a client opens it. Its transcript and its inbox are as they were."
- The `id` takes `<id>`, `@<id>`, `<short id>`, `@<short id>` and `@<slug>` through the one resolver (`SessionsAddressReader.swift`). For this operation only, a short id and a slug match only the archived sessions that the caller can see: first the folder of the caller, then all of them. Two matches give `AMBIGUOUS_REFERENCE` with the id, the title and the folder of each. The other operations keep the rule "an archived session matches only its id".
- The answer gives the session, its agent and its folder, as the archive answer does.
- A session that is not archived gives the corrective with a new code `NOT_ARCHIVED` (`SessionsRefusal.swift`).
- Add `Mutation.unarchiveSession(input: UnarchiveSessionInput { id })` with the same actor and visibility rules as `archiveSession` (`context.actor(of:)`, `requireVisible`). It gives the session. A session that is not archived gives the coded error `NOT_ARCHIVED`. Do not make it silent: Testudo treats `NOT_ARCHIVED` and `ARCHIVED_SESSION` as success for its undo and redo.
- The tool/endpoint parity test (MT-10) must stay green: the tool and the mutation give the same corrective.
- Aliases (D86) for the new names. Re-record the golden schema; the diff must only add lines.

## Tests

- [ ] Tool: archive, then `unarchive session` by `@<slug>` of the archived session; by short id; by full id.
- [ ] Tool: an ambiguous slug of two archived sessions gives `AMBIGUOUS_REFERENCE`.
- [ ] Tool: a session that is not archived gives `NOT_ARCHIVED`.
- [ ] Tool: `rename session` with the slug of an archived session still finds no session.
- [ ] Graph: `unarchiveSession` gives the session with the state `IDLE`; a second call gives `NOT_ARCHIVED`.
- [ ] Graph: the unarchive gives one `changed` entry on `changes(after:)`. #sessions #archive #graphql