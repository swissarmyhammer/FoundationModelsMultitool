---
assignees:
- claude-code
depends_on:
- 01M7TXXYXSTM71VFGJAY8M7YVR
position_column: todo
position_ordinal: '8380'
title: SessionImporter, and list imports and import session in the sessions tool (D209)
---
Decision: D209 (l), (n) in TestudoApp/features/decisions.md (commit 56a8a59). Brief: /Users/wballard/github/swissarmyhammer/.briefs/import/mt-brief.md, items 1, 2, 3 and 5. Read the brief for the exact types.

Precondition: ^y8m7yvr (the share task changes the same host API and files; do this after it). No external dependency: a fake importer in the tests. FoundationModelsACPAgent waits on the protocol of this task: push it first.

## Work

- New file `Capabilities/Sessions/SessionImporter.swift`, in the style of `SessionTranscriptExporter.swift`: `public protocol SessionImporter: Sendable` with `importable(_:)` and `importSession(_:)`, and the public types `ImportableSessionsRequest`, `ImportableSession`, `SessionPreviousImport`, `ImportableSessionsPage`, `SessionImportOrder`, `SessionImportResult` (Sendable, Equatable, Codable, public memberwise inits).
- Host API: add `importer` (nil by default) to `SessionsTool.init` and `SessionsGraph.endpoint(of:...)`, after `sharer`, with the `storeIfPresent` and `read` helpers. Each current caller still compiles.
- `list imports` (`listImports`): `agent`, `folder` (`.` is the caller folder), `limit` (20). One plain-text line for each session: the agent, the source id, the title, the folder, the date, the number of turns, and "imported <date> as @<short id>" for each previous import, as information only. For each agent in `unreadableSources`: "No access to the sessions of <agent>. Ask the user to run Import Sessions…".
- `import session` (`importSession`): `agent`, `source`, `folder`, `name`. Each call makes a new session, also when the source was imported before (Q85): no `again` argument. The answer gives `@<short id>`, the name and the count of the skipped records. No grant: the corrective of `list imports`. A folder that does not exist or has no grant: a corrective that names the `folder` argument.
- No importer: a corrective for both operations (for example `IMPORT_UNAVAILABLE`).
- Put the steps in shared functions that the endpoint task can reuse.
- Add one example row and the parameter list for each new operation to `SKILL.md`, so SessionsSkillTests stays green. The rest of the skill text is a later task.
- Aliases (D86). After the push, send the sha to `foundationmodelsacpagent-9e` and `testudoapp-9a`.

## Tests

- [ ] With a fake importer: the text of both answers, `previousImports`, `folder: .`.
- [ ] A second import of the same source gives a second session.
- [ ] No importer; no grant; a folder with no grant: the correctives. #sessions #import