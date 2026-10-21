---
assignees:
- claude-code
position_column: todo
position_ordinal: 8b80
title: 'SessionsGraph: Session.ownedByViewer and hasOwner (session.md 11.2)'
---
## What
session.md section 11.2 sketches `ownedByViewer: Boolean!` (D11: this client owns the session now) and `hasOwner: Boolean!` on `Session`. ^9c0fp9m shipped the queries without them: their value comes from the owner registry of ACPAgent (ACPA-5, ACPA-13) through `GraphQLViewer.ownedSessions` / `clientOwnedSessions`, and a call with no viewer (the agent) has no answer for either.
- Decide the value for a call with no viewer, then add both fields to `SessionsGraphSession` in `Sources/FoundationModelsMultitool/Capabilities/Sessions/SessionsGraphSchema.swift` / `SessionsGraphTypes.swift`, reading `context.sessions.viewer`.
- Update `Tests/FoundationModelsMultitoolTests/Goldens/sessions.graphql` (an added field keeps version 1).

## Tests
- [ ] Case in `SessionsGraphQueryTests`: an external viewer that owns a session reads `ownedByViewer: true`, `hasOwner: true`; a session owned by another client reads `ownedByViewer: false`, `hasOwner: true`.
- [ ] `swift test --filter SessionsGraph` passes. #graphql #sessions