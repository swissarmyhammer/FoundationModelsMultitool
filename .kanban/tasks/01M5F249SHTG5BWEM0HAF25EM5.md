---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5f3wy98g6fw28mzj1tptaf3
  text: 'EXTRAS-10 landed (Extras f126153, on origin). Drop the interim local NOT_FOUND: use `GraphQLToolkitError.notFound(kind:id:)` from the toolkit. For changes cards: `ChangeLog<Event>` + `ChangeLogEntry`, and `ChangedIDs`/`IDChange` in IDChange.swift fit SessionChange.'
  timestamp: 2026-10-21T11:35:14.984742+00:00
depends_on:
- 01M5F23YY9X0YEG7M1D9C0FP9M
- 01M5F23F0NMKMEXGZESNEZB6S0
- 01M5F23K19C0N3TH4A2AZJPXDF
position_column: todo
position_ordinal: '8880'
title: SessionsGraph mutations (MT-10)
---
## What
In `Sources/FoundationModelsMultitool/Capabilities/Sessions/SessionsGraph.swift`, under EXTRAS-9 rule 7 (TestudoApp `features/packages/foundationmodels-extras.md`):
- `startSession`, `tagSession`, `untagSession`, `renameSession`, `sendMessage`, `replyMessage`, `archiveSession`, each `verbNoun(input: VerbNounInput!)`, named after the tool verbs in code mode. Each returns the changed `Session` (send/reply return the receipt).
- The alias tables accept the bare verbs of `session.md` 14 (`start`, `tag`, `untag`, `rename`, `send`, `reply`, `archive`); rewrites show in `extensions.rewrites`.
- A start from a client opens a tab only for that client (section 11.5, D90). `StartSessionInput` has no `openInTab`.
- Mutation rules of section 11.3: an `external` viewer acts only on sessions it can see, otherwise `NOT_FOUND`. Until EXTRAS-10 adds `NOT_FOUND` to the toolkit, use the same code string from the package's own `SessionsGraphError: CodedError`; leave a TODO naming EXTRAS-10 to switch to the toolkit constant.
- The tool ops and the mutations share the correctives and limits, so both give the same refusal text.

## Acceptance Criteria
- [ ] Each mutation changes the `InMemorySessionDirectory` the same way the matching tool op does
- [ ] Each bare-verb alias works and is reported in `extensions.rewrites`
- [ ] An external viewer gets `NOT_FOUND` (from `SessionsGraphError` until EXTRAS-10) for a session it cannot see
- [ ] The SDL golden is updated

## Tests
- [ ] New `Tests/FoundationModelsMultitoolTests/SessionsGraphMutationTests.swift`, including a parity test that runs each tool op and its mutation on two fresh directories and compares the result
- [ ] `swift test --filter SessionsGraph` passes

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #graphql #sessions