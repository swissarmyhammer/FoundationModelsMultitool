---
assignees:
- claude-code
depends_on:
- 01M14DQ9JWB41F16JVAYVV1AMA
position_column: todo
position_ordinal: '9580'
title: Remove the FoundationModelsCodeContext dependency from Package.swift
---
## What
All work is in `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool`.

Change `Package.swift`:
- Remove the `FoundationModelsCodeContext` package dependency (near line 37).
- Remove the `.product(name: "FoundationModelsCodeContext", ...)` entry from the `FileTool` target (near line 55).
- Rewrite the platform header comment (near line 9). It must not give `FoundationModelsCodeContext` as the reason for the macOS 27 floor. Keep the floor value. State the real remaining reason: the FoundationModels v2 API level.
- Rewrite the products and target comments that name the `DiagnosticsBridge` (near lines 19 and 45).
- Rewrite the integration-target comment (near lines 83-85). It must not describe a live `sourcekit-lsp` tier.

Then run `swift package resolve` so `Package.resolved` drops the removed package.

## Acceptance Criteria
- [ ] `rg -l "CodeContext|sourcekit-lsp" Package.swift Package.resolved Sources Tests` finds no match.
- [ ] `swift package show-dependencies` does not list `FoundationModelsCodeContext`.
- [ ] The full test suite passes.

## Tests
- [ ] This task changes the manifest only. Do not add new tests.
- [ ] Run `cd /Users/wballard/github/swissarmyhammer/FoundationModelsFileTool && swift build && swift test`. Expect zero failures.

## Workflow
- Use `/tdd` where new code is written. This task has no new code, so the build and the suite are the checks. #filetool-pure-edit #lsp