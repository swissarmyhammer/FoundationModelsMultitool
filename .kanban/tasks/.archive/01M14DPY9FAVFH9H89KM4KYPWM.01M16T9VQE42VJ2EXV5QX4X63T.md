---
assignees:
- claude-code
depends_on:
- 01M14DPJKZ87SK60908VEN17JT
position_column: todo
position_ordinal: '9380'
title: Remove the diagnostics field from the write and edit operations
---
## What
All work is in `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool`.

Remove the diagnostics output from the two mutating operations:
- `Sources/FileTool/Operations/WriteFile.swift`: remove the `diagnostics: FileDiagnostics?` output field, its initializer parameter, and the `await context.diagnostics.diagnose(fileAt: url)` call (near line 224). Update the field's doc comments, and the output-shape doc comment near line 78 that lists the `diagnostics` field.
- `Sources/FileTool/Operations/EditFile.swift`: do the same. The field is near line 224, the call is near line 477, and a `diagnostics: nil` argument is near line 520. Also rewrite the `context` parameter doc near line 456. It must not say the context supplies a diagnostics bridge.
- The removed `await` calls can leave `async` paths that no longer suspend. Remove each `await`/`async` marker the compiler then flags. The build must stay warning-free.
- `Sources/FileTool/FileToolCLI.swift`: rewrite the comment that points to `DiagnosticsBridge/maximumReportedItemCount` (near line 134). Point it at a different internal-for-testability example, or remove the reference.

Update the unit tests in the same change:
- `Tests/FileToolTests/FileChangeSetTests.swift`: remove `"diagnostics"` from the expected wire-key lists (near lines 465 and 482).
- `Tests/FileToolTests/ReadmeSnippetTests.swift`: remove the diagnostics snippet assertions. If the test quotes `README.md` lines, update those exact README lines so the parity test passes. A full README rewrite is a later task.

## Acceptance Criteria
- [ ] The `write file` and `edit file` JSON outputs have no `diagnostics` key.
- [ ] `rg -n "context\.diagnostics" Sources` finds no match.
- [ ] `swift build` emits no warnings.
- [ ] The full test suite passes.

## Tests
- [ ] Update the wire-key assertions in `Tests/FileToolTests/FileChangeSetTests.swift`. They are the regression test for the output shape.
- [ ] Run `cd /Users/wballard/github/swissarmyhammer/FoundationModelsFileTool && swift test`. Expect zero failures.

## Workflow
- Use `/tdd` — change the wire-key assertions first, see them fail, then change the operations to make them pass. #filetool-pure-edit #lsp