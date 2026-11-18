---
assignees:
- claude-code
depends_on:
- 01M7QCBB4ARPTB8SNGHZKEWPEX
position_column: todo
position_ordinal: '8680'
title: SessionTranscriptExporter and the export session operation of the sessions tool (D202)
---
Decision: D202 in TestudoApp/features/decisions.md (commit 40450ab). Brief: /Users/wballard/github/swissarmyhammer/.briefs/export-markdown/mt-brief.md, items 1, 2 and 5. Overview: overview.md in the same folder.

Order: do this after the D199 and D200 tasks. The `id` takes the same input as the change operations, so this task depends on ^zkewpex. FoundationModelsACPAgent gives the real exporter, and it waits on the protocol of this task.

This package does not link FoundationModelsACP. Thus the host gives the Markdown through a protocol.

## Work

- Add `public protocol SessionTranscriptExporter: Sendable { func markdown(of session: ULID, includeThoughts: Bool) async throws -> String }`.
- `SessionsTool.init(directory:exporter:)` takes an optional exporter (default `nil`). `SessionsGraph.endpoint(of:exporter:)` keeps it with the one endpoint of the directory (`SessionsGraph.swift:143`), for the endpoint field of the next task.
- Add the operation `export session` (`exportSession` in code mode) to `SessionsTool` (`SessionsTool.swift:16-30`, `:71-91`). Parameters:
  - `id`: optional. The same forms as the change operations (^zkewpex): `<id>`, `@<id>`, `<short id>`, `@<short id>`, `@<slug>`. The default is the caller session.
  - `format`: optional, `markdown` by default. Each other value gives a corrective that names `markdown`.
  - `thoughts`: optional Boolean, `false` by default. It goes to the exporter as `includeThoughts`.
  - `path`: optional. A file name or a relative path in the session folder. The default is `<slug>.md` of the summary of the session. An absolute path or a path with `..` that goes out of the session folder gives a corrective and writes nothing.
  - `replace`: optional Boolean, `false` by default. When the file exists and `replace` is false, the operation writes nothing and gives a corrective that tells the path and `replace`.
- The operation resolves the session through the visibility of the context, calls the exporter, and writes the text to the file in the `workingDirectory` of the session with an atomic write.
- The answer is plain text: the path of the file, the number of lines, and the title of the session. It does not give the text (D202 (g): a transcript can be larger than the context window).
- With no exporter: a corrective that says this server cannot export, and names the UI command Export as Markdown….
- Add the description of the operation to `SessionsToolText`, in the style of the other operations. Add aliases for the new names (D86).

## Tests

- [ ] With a fake exporter, `export session` with no `id` writes `<slug>.md` of the caller in its folder, and answers with the path, the number of lines and the title.
- [ ] `@<short id>` and `@<slug>` name the same session as the id.
- [ ] An existing file and no `replace`: no write, a corrective. With `replace: true`: the file is replaced.
- [ ] `path` with `..` or an absolute path: a corrective, no write.
- [ ] `format: html`: a corrective that names `markdown`.
- [ ] `thoughts: true` goes to the exporter.
- [ ] No exporter: a corrective, no write.
- [ ] A session that the caller cannot see is not found.
- [ ] The existing session tool tests stay green. #sessions #export-markdown