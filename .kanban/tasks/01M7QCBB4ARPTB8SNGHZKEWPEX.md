---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m7qhynf4tmmkp2ebaswthz1e
  text: |-
    Research (implement).
    - `SessionReference.resolve` of Extras never matches an archived session. Thus a full id (with or without `@`) must not go through the resolver: `check session` of an archived session and the "archived already" corrective of `archive session` need the direct id lookup. The `send message` reader does the same (`.id` form gives the id directly).
    - The tool reads the directory with no viewer (EXTRAS-9 rule 4: the agent sees each session). Thus in the tool only an archived session is "not visible" to a slug. The visibility filter of the shared reader shows with an external viewer; the test for "a slug of a session that the caller cannot see" calls the shared reader on `SessionsVisibility` with an external viewer.
    - A text with no `@` names a session only by its short id, as in the `send message` reader. I will move the short-id filter of `address(ofShortID:)` into one shared function, so both readers use it (D100).
    - `SessionsToolText.ambiguousReference` says "The message was not sent." For the change operations the sentence must say that nothing changed. I will give it the outcome sentence as an argument.
    - GraphQL mutations (`tagSession`, `untagSession`, `renameSession`, `pinSession`, `unpinSession`, `archiveSession`) take `id: ID!` through `SessionsGraphInput.sessionID` (ULID only). D100 (a) asks only that the agent can do what the UI can; it does not ask that the endpoint ids take a short id. No test kit asks for it. The endpoint ids stay as they are, and keep the old corrective text of a ULID (`INVALID_SESSION_ID`).
  timestamp: 2026-11-18T14:46:10.660894+00:00
- actor: claude-code
  id: 01m7qjh2svvh4k5gy0pds28vdy
  text: |-
    Implementation landed.
    - One reader: `SessionsVisibility.sessionID(referencedBy:lookupFolder:)` and `sessionID(referencedBy:callerID:)` in SessionsAddressReader.swift. A full id (with or without @) gives its id directly, so an archived session is still found by its id. For a short id or a slug, the reader uses `resolution(of:lookupFolder:)`. A text with no @ goes through the new shared `shortIDResolution`, which `send message` now uses too. An ambiguous reference gives AMBIGUOUS_REFERENCE with the sentence "Nothing changed.". `ambiguousReference` now takes an `outcome` sentence. No match gives INVALID_SESSION_ID with the new `notASessionID`, which names `listSessions`. The reader never starts an agent.
    - The tool: `check session`, `rename session`, `pin session`, `unpin session`, `tag session`, `untag session` and `archive session` use the reader, with the folder of the caller first. An absent id still means the caller. `@Guide` of each `id` is updated. `reply message` is not changed.
    - GraphQL: there is a test kit that demands a change. `SessionsGraphMutationTests` "each mutation refuses with the corrective of its tool op" (MT-10, session.md 11.4 parity) failed when only the tool changed: the INVALID_SESSION_ID text was different. Thus `tagSession`, `untagSession`, `renameSession`, `pinSession`, `unpinSession` and `archiveSession` now read `id` through the same reader (`SessionsGraphContext.referencedSession`), with the visibility of the viewer. The agent looks in the folder of its caller first. A client looks in all sessions. The id descriptions and the golden `sessions.graphql` are updated. The query `session(id:)`, `inbox`, the reply `sessionId`, `fromSession` and the list filters stay full-id only, with the old text, now named `notAFullSessionID`.
    - Two guard tests passed before the change. Today's code also refuses them, for a different reason: the hidden slug, and the no-match slug that must not start an agent. They now guard the new resolver path.
  timestamp: 2026-11-18T14:56:14.139107+00:00
- actor: claude-code
  id: 01m7qjh6d76e349qb6x00964gc
  text: |-
    ### implement — changed
    - evidence: 10 source/test files plus 1 golden file. Sources/FoundationModelsMultitool/Capabilities/Sessions/{SessionsAddressReader, SessionsToolInput, SessionsToolContext, SessionsToolChangeOperations, SessionsToolOperations, SessionsToolText, SessionsToolText+Messages, SessionsToolText+Changes, SessionsGraphMutations}.swift; Tests/.../SessionsToolReferenceTests.swift (new, 8 tests); Tests/.../SessionsGraphMutationTests.swift (+2 tests); Tests/.../Goldens/sessions.graphql. `swift build` clean. `swift test --filter "SessionsTool|SessionsGraph"`: 197 tests, 1 test bug found and fixed (tags given as a string), then `--filter SessionsToolReferenceTests` 8/8 passed. Full `swift test`: 3034 tests in 271 suites passed, 0 failures.
    - next: review
  timestamp: 2026-11-18T14:56:17.831486+00:00
depends_on:
- 01M7NQMS04V5B1WKXMY6XZNEGM
position_column: doing
position_ordinal: '80'
title: The session id of check session and of each change operation takes a short id and @slug (D200)
---
Decision: D200 (e) in TestudoApp/features/decisions.md, after D199. Brief: /Users/wballard/github/swissarmyhammer/.briefs/at-sessions/mt-brief-sessions-skill.md, item 3.

Precondition: the address reader of ^6xznegm. Use the same resolver. Do not write a second lookup (D100).

## Current behavior

The `id` of `check session`, `rename session`, `pin session`, `unpin session`, `tag session`, `untag session` and `archive session` is a full ULID only: `SessionsToolInput.sessionID(_:)` (`Capabilities/Sessions/SessionsToolInput.swift:44-78`) through `ulid(_:)` (`:142`). The skill of D200 gives examples with a short id, so they fail today.

## Work

- The `id` of each of these operations takes `<id>`, `@<id>`, `<short id>`, `@<short id>` and `@<slug>`, with the resolver of ^6xznegm, filtered by the visibility of the caller. The lookup looks first in the folder of the caller.
- The resolver is async, so the sync `sessionID(_:)` becomes an async reader for these operations. An `id` that is absent still means the caller session, where it does so today.
- An ambiguous reference gives the corrective with the id, the name and the folder of each match, and changes nothing.
- A reference with no match gives the corrective that names `list sessions`. It does not start an agent: only `send message` starts an agent.
- Update the `@Guide` text of each `id`, and `SessionsToolText.notASessionID`.
- The `reply message` operation keeps a message id. This task does not change it.

## Tests

- [ ] `rename session` with a short id acts on that session.
- [ ] `pin session` with `@<slug>` acts on that session.
- [ ] `archive session` with `@<short id>` acts on that session.
- [ ] `check session` with a full id, with and without `@`, still works.
- [ ] An ambiguous slug gives the corrective with each match and changes nothing.
- [ ] A slug of a session that the caller cannot see is not a match.
- [ ] The existing session tool tests stay green. #sessions #at-sessions