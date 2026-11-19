---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m7tzqvtrr73mjwh7m2tarrek
  text: |-
    Research done. Findings:
    - The share task (7c2f6355) gives the pattern: a protocol file, an operations file with static shared steps on SessionsToolContext, a text file, a fixture fake. SessionsGraph keeps each host value in a Mutex with storeIfPresent/read.
    - Extras 4f3afb5: InMemorySessionDirectory.importSession(_:transcript:) makes a recorded root session with origin import and the next free name. The fake importer in the tests calls it, so the tool reads the real name and short id back from the directory.
    - The brief gives no error type for "no grant" and "folder has no grant" in import session. The importer must tell these cases to the tool, so this task adds the public enum SessionImportError (sourceUnreadable(agent:), folderUnavailable(URL)). ACPAgent must throw these cases.
    - folder "." uses the caller folder. The search reader has the private helper searchFolder and the constant noCallerFolder (text says "The search did not run."). This task makes the helper internal with an outcome sentence, so list imports and import session reuse it.
    - ACPAgent origin/main calls SessionsTool(directory:exporter:searcher:) and SessionsGraph.endpoint(of:); a trailing defaulted importer parameter keeps these calls valid.
  timestamp: 2026-11-19T22:44:51.160253+00:00
- actor: claude-code
  id: 01m7v09vybcf54x985nnshzctc
  text: |-
    ### implement — changed
    - evidence: new files Sources/.../Sessions/SessionImporter.swift, SessionsToolImportOperations.swift, SessionsToolText+Import.swift, Tests/.../SessionsToolImportTests.swift, Tests/.../Fixtures/SessionImporterFixtures.swift. Changed: SessionsTool.swift, SessionsGraph.swift, SessionsToolContext.swift, SessionsRefusal.swift, SessionSearchRequestReader.swift, SessionsToolText.swift, SessionsToolText+Search.swift, SessionSharer.swift, SessionTranscriptExporter.swift, SessionTranscriptSearcher.swift (doc links), SKILL.md, SessionsSkillTests.swift. Extras updated to cdc6179 (Package.resolved is git-ignored). swift build: green. swift test --filter SessionsToolImportTests: 27 passed. Full swift test: 3287 tests in 284 suites passed, 0 failures; the one warning is the SPM build-system note on the mlx bundle, not from source.
    - notes: new public enum SessionImportError (sourceUnreadable(agent:), folderUnavailable(URL)) — the brief gave no way for the importer to tell these two cases; ACPAgent must throw them. New codes: IMPORT_UNAVAILABLE, NO_SOURCE_ACCESS, IMPORT_FOLDER_UNAVAILABLE, IMPORT_FAILED; IMPORT_UNSUPPORTED stays the directory error. Shared steps for ^fr3tyrn: SessionsVisibility.importables(_:with:) and importSession(_:with:) (the second gives the SessionSummary of the directory), SessionsToolContext.requiredImporter/importerResult/refusal(for:). Verb alias copy -> import; parameter aliases from/sourceAgent, sourceId/path, cwd, title, first. import session needs a caller session (as start session). ACPAgent origin/main b319166 uses only SessionsTool(directory:exporter:searcher:) and SessionsGraph.endpoint(of:), so the defaulted importer keeps it compiling (static check). Not committed, not pushed: the sha messages to the peers follow the push.
    - next: /review
  timestamp: 2026-11-19T22:54:41.099524+00:00
- actor: claude-code
  id: 01m7v0newwpw44gdaqynvaf45w
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (d8bfae93): 0 findings, 0 confirmed, 4 refuted, 14 attempted, 0 failed. SKILL.md was not reviewed: no validator matches this file.
    - next: none. The task is in done.
  timestamp: 2026-11-19T23:01:00.956897+00:00
- actor: claude-code
  id: 01m7v0nvb3pwsrmvbf7bk6rf08
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — SessionImporter.swift, SessionsToolImportOperations.swift, SessionsToolText+Import.swift (new); SessionsTool, SessionsGraph, SessionsToolContext, SessionsRefusal, SessionSearchRequestReader, SessionsToolText(+Search); SKILL.md (rows); SessionsToolImportTests (27), SessionImporterFixtures; local pin Extras cdc6179
    - test: green — swift test, 3287 passed (run in the implement step)
    - commit: d8bfae93
    - review: clean — 0 findings; the public `SessionImportError` beyond the brief is intended
  timestamp: 2026-11-19T23:01:13.699124+00:00
depends_on:
- 01M7TXXYXSTM71VFGJAY8M7YVR
position_column: done
position_ordinal: ffffffffa380
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

- [x] With a fake importer: the text of both answers, `previousImports`, `folder: .`.
- [x] A second import of the same source gives a second session.
- [x] No importer; no grant; a folder with no grant: the correctives. #sessions #import