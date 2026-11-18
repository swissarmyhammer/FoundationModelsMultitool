---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m7nqpvp52ybypxd4kp761nkh
  text: 'Extras API (from the Extras session, 2026-11-17): `SessionReference.resolve(_:sourceFolder:among:)` gives `.session`, `.ambiguous` or `.none`. Map `.none` with an agent folder of the name to `startsAgent: true`.'
  timestamp: 2026-11-17T21:48:17.477279+00:00
- actor: claude-code
  id: 01m7qbran74mgnc8ady600nhv8
  text: |-
    ### dropped — no client needs it
    - evidence: 2026-11-18, the TestudoApp session: the app does not call `resolveSession`. It resolves `@` tokens in memory with `SessionReference.resolve(_:sourceFolder:among:)` over its own list of sessions (`id shortId slug title cwd`). No other client asks for the query.
    - next: archived. Make a new task when a client needs a resolver on the endpoint.
  timestamp: 2026-11-18T12:57:51.527745+00:00
depends_on:
- 01M7NQM8VTYF6G2ZW1QGRJJ9R4
- 01M7NQMS04V5B1WKXMY6XZNEGM
position_column: todo
position_ordinal: '8380'
title: resolveSession query for the mention marks of the composer (D199)
---
Decision: D199 (d), (e), (h) in TestudoApp/features/decisions.md. Brief: /Users/wballard/github/swissarmyhammer/.briefs/at-sessions/mt-brief-at-sessions.md, item 5 and item 6.

Precondition: FoundationModelsExtras gives `SessionReference.resolve` on origin/main. Before you start, examine origin/main of ../FoundationModelsExtras. This task uses the `Session.shortId` and `Session.slug` fields of ^grjj9r4 and the address reader of ^6xznegm.

## Work

- Add the query `resolveSession(ref: String!, from: ID): SessionResolution!` to the `sessions` endpoint.
- `SessionResolution` has `session: Session`, `matches: [Session!]!`, `startsAgent: Boolean!` and `reason: String`.
- `startsAgent` is true when no session matches `@<name>` and an agent folder has the name, so a send starts that agent.
- The query calls the same `SessionReference.resolve` as the address reader, with the visibility of the viewer, and the folder of the `from` session as the first lookup folder. Do not write a second lookup.
- The query sends nothing.
- Add the aliases of the new names (D86).

## Tests

- [ ] One match gives `session` and `matches` with one session.
- [ ] An ambiguous slug gives `session: null` and each match in `matches`.
- [ ] No match gives `session: null` and a `reason`.
- [ ] `@<agent name>` with no session and an agent folder gives `startsAgent: true`.
- [ ] A session that the viewer cannot see is not a match.
- [ ] The directory gets no message. #sessions #at-sessions #graphql #blocked-external