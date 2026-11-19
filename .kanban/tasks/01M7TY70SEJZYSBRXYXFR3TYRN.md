---
assignees:
- claude-code
depends_on:
- 01M7TY6PWAXJH82MDJ5ET3QN9R
- 01M7TXY9WWWR9TADTG8YSYBPDP
position_column: todo
position_ordinal: '8480'
title: importableSessions and importSession on the sessions endpoint (D209)
---
Decision: D209 (l) in TestudoApp/features/decisions.md (commit 56a8a59). Brief: /Users/wballard/github/swissarmyhammer/.briefs/import/mt-brief.md, item 4.

Precondition: ^et3qn9r (the protocol, the host API and the shared import steps; reuse them, do not copy them) and ^ysybpdp (the share endpoint task changes the same endpoint files; do this after it).

## Work

- The query `importableSessions(agent: String, folder: String, first: Int = 20, after: String)` and the mutation `importSession(input: {agent, source, folder, name})`, with GraphQL types for the protocol types of ^et3qn9r (`ImportableSession`, `SessionPreviousImport` with `session: Session` and `importedAt: DateTime`, the page with `nextCursor` and `unreadableSources`).
- The mutation gives the `Session` of the directory. Each call makes a new session.
- The visibility and actor rules of the other mutations. The tool/endpoint parity test (MT-10) stays green: the same correctives.
- No importer: the refusal with the text of the tool corrective.
- Follow D115 (EXTRAS-9) and keep the EXTRAS-11 kit green. Aliases (D86). Re-record the golden schema; the diff only adds lines.

## Tests

- [ ] `importableSessions` with a fake importer, with `previousImports` and `unreadableSources`.
- [ ] `importSession` gives the new Session; a second call gives a second session.
- [ ] No importer: the refusal.
- [ ] The SDL has the new types. #sessions #import #graphql