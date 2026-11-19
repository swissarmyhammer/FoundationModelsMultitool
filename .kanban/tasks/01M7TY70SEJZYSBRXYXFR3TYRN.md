---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m7v2505gtqhrgqvbnpkkg0t2
  text: |-
    Research done. Findings:
    - The shared steps are `SessionsVisibility.importables(_:with:)` and `importSession(_:with:)` in SessionsToolImportOperations.swift. The list step gives `ImportableSessionsOutcome` with `shortIDs` of the visible earlier imports. The endpoint needs the summary of each visible earlier import, so the plan changes the outcome to keep the summaries (`summaries: [ULID: SessionSummary]`). The tool text then reads the short id from the summary. This keeps one visibility read for the tool and the endpoint.
    - The endpoint context (`SessionsGraphContext`) has no importer yet; the endpoint already stores one (`SessionsGraph.importer`). Add it to the context.
    - Decisions: (1) a `previousImports` entry whose session the viewer cannot see is dropped, so `session: Session!` is non-null and the page does not tell that the session exists (as `unavailableFolders` of the search). (2) `.` in `folder`: for a call with no viewer (the agent) it is the folder of the caller session, as in the tool; for a client there is no caller session, so `.` gives INVALID_FOLDER with the tool corrective. (3) An external client cannot import (as `startSession`): UNTRUSTED_CLIENT. It can list. (4) The mutation checks the actor first (MISSING_CALLER for the agent with no caller session), as fork and share do.
    - Tests: new suite SessionsGraphImportTests; refusal parity row IMPORT_UNAVAILABLE in SessionsGraphMutationTests; golden sessions.graphql re-record.
  timestamp: 2026-11-19T23:26:58.736064+00:00
- actor: claude-code
  id: 01m7v2nz0qp5mbmn6930zsdmec
  text: |-
    ### implement — changed
    - evidence: new Sources/FoundationModelsMultitool/Capabilities/Sessions/SessionsGraphImport.swift (types, resolvers, schema); changed SessionsGraph.swift (context importer, aliases D86, docs), SessionsGraphSchema.swift (context field, type and field registration), SessionsGraphMutations.swift (`importSession` mutation entry, `externalImport` corrective, field list), SessionsToolImportOperations.swift and SessionsToolText+Import.swift (`ImportableSessionsOutcome.summaries` in place of `shortIDs`, one visibility read for tool and endpoint); tests: new SessionsGraphImportTests.swift (25 tests), IMPORT_UNAVAILABLE parity row in SessionsGraphMutationTests.swift; golden sessions.graphql re-recorded with GRAPHQL_GOLDEN_RECORD=1: 108 lines added, 0 removed.
    - RED: `swift test --filter "SessionsGraphImportTests|SessionsGraphMutationTests"` 59 tests, 42 issues (fields missing). Affected suites: `--filter "SessionsGraph|SessionsTool|SessionsSkill"` 436 tests, 5 issues, all in my new tests (directory URL of a folder argument has a trailing slash; fixed the expected values and the folder case of the refusal row). Re-run of SessionsGraphImportTests only: 25 passed. Full `swift test`: 3331 tests in 286 suites passed, 0 issues, exit 0.
    - Decisions (documented in the file header and the SDL): an earlier import whose session the viewer cannot see is dropped; `.` is the caller session folder for the agent and INVALID_FOLDER for a client; an external client cannot import (UNTRUSTED_CLIENT) but can list.
    - next: /review
  timestamp: 2026-11-19T23:36:14.615267+00:00
depends_on:
- 01M7TY6PWAXJH82MDJ5ET3QN9R
- 01M7TXY9WWWR9TADTG8YSYBPDP
position_column: doing
position_ordinal: '80'
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

- [x] `importableSessions` with a fake importer, with `previousImports` and `unreadableSources`.
- [x] `importSession` gives the new Session; a second call gives a second session.
- [x] No importer: the refusal.
- [x] The SDL has the new types. #sessions #import #graphql