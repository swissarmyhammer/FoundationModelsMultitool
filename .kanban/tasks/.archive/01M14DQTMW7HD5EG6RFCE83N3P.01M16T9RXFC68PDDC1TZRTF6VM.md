---
assignees:
- claude-code
depends_on:
- 01M14DQHG7T0QJK8JTH0A3H1M4
position_column: todo
position_ordinal: '9680'
title: Update the README and the design notes after the diagnostics removal
---
## What
All work is in `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool`.

The CI workflow changes moved to the first task of this chain, so this task is documents only:
- `README.md`: remove the diagnostics feature text and each `FoundationModelsCodeContext` reference. Describe the tool as a pure file-edit tool. Keep every remaining doc-snippet block a real, contiguous excerpt of its source file.
- `DESIGN_NOTES.md`: remove or mark as historical each `CodeContext` and diagnostics-bridge section.
- Do not edit `plan.md`. It is a historical record.

## Acceptance Criteria
- [ ] `rg -l "CodeContext|sourcekit-lsp|DiagnosticsBridge" README.md` finds no match.
- [ ] `Tests/FileToolTests/ReadmeSnippetTests.swift` passes against the new README.
- [ ] The full test suite passes.

## Tests
- [ ] `Tests/FileToolTests/ReadmeSnippetTests.swift` is the automated check for the README. Keep it aligned with the new README text.
- [ ] Run `cd /Users/wballard/github/swissarmyhammer/FoundationModelsFileTool && swift test`. Expect zero failures.

## Workflow
- Use `/tdd` where new code is written. This task changes documents, so the README parity test and the suite are the checks. #filetool-pure-edit #lsp