---
assignees:
- claude-code
depends_on:
- 01M14DPY9FAVFH9H89KM4KYPWM
position_column: todo
position_ordinal: '9480'
title: Delete the DiagnosticsBridge and make FileContext bridge-free
---
## What
All work is in `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool`.

Delete the diagnostics runtime:
- `Sources/FileTool/DiagnosticsBridge.swift`
- `Sources/FileTool/FileDiagnostics.swift`
- `Sources/FileTool/NullEmbedder.swift`

Change `Sources/FileTool/FileContext.swift`:
- Remove the `diagnostics` property.
- Remove the `eagerWarmup` parameter.
- Remove the designated initializer that takes a `DiagnosticsBridge`. Collapse to one initializer. Keep `additionalRoots` — tests depend on it.
- Remove `stop()`.
- Keep the type `public`.
- Use `Sources/FoundationModelsMultitool/Capabilities/Files/FileContext.swift` in `/Users/wballard/github/swissarmyhammer/FoundationModelsMultitool` as the model shape.

Remove every `stop()` and `eagerWarmup` call site in the same change:
- `Examples/FileDemo/Sources/file-demo/ReadmeExample.swift`: drop `eagerWarmup: true` (near line 30) and `await context.stop()` (near line 50).
- `Examples/FileDemo/Sources/file-demo/ChatValidationHarness.swift`: delete this file. Its purpose is the read → edit → diagnostics loop, which no longer exists. Remove each call site of the harness in the `file-demo` target.
- `Tests/FileToolIntegrationTests/ScriptModeTests.swift` (near lines 76, 79, 107, 110, 126), `Tests/FileToolIntegrationTests/ChangeSetPatchTests.swift` (near lines 181, 227), and `Tests/FileToolIntegrationTests/Support/FusedToolWorkspace.swift` (near lines 49, 52): remove the `await context.stop()` calls and any comments about them.

Keep the README parity test green:
- `README.md`: delete the doc-snippet block that quotes `Sources/FileTool/FileDiagnostics.swift` (near lines 70-88). Update the `ReadmeExample.swift` excerpt block (near lines 24-54) so it matches the new example source with no `eagerWarmup` and no `stop()`.
- `Tests/FileToolTests/ReadmeSnippetTests.swift`: drop the `FileDiagnostics.swift` entry from `requiredSources` and any related assertions.

Other tests and docs:
- Delete `Tests/FileToolTests/DiagnosticsBridgeTests.swift`.
- Delete `Tests/FileToolTests/UpstreamVisibilityTests.swift`. It only probes the upstream `FoundationModelsCodeContext` API.
- `Tests/FileToolTests/FileContextTests.swift`: remove the `stop()` test and the `context.diagnostics` use (near lines 11 and 39). Keep the other tests. Add a test that builds a `FileContext` with the collapsed initializer and checks `root`, `readOnly`, and the journal mode.
- `Tests/FileToolTests/DocCCoverageTests.swift`: there is no coverage list. The scanner reads `Sources/FileTool` from disk. Only remove `DiagnosticsBridge.Mode` from the suite's own doc comment.
- `Sources/FileTool/FileChangeJournal.swift`: update the doc comment that names the old initializer signature (near line 14).

## Acceptance Criteria
- [ ] `rg -l "DiagnosticsBridge|FileDiagnostics|NullEmbedder|eagerWarmup|\.stop\(\)|context\.diagnostics" Sources Tests Examples` finds no match.
- [ ] `FileContext` has one initializer and no `stop()`.
- [ ] `swift build` compiles the whole package, `file-demo` included, with no warnings.
- [ ] `swift test --filter ReadmeSnippetTests` passes.
- [ ] The full test suite passes.

## Tests
- [ ] Add the collapsed-initializer test to `Tests/FileToolTests/FileContextTests.swift`.
- [ ] Run `cd /Users/wballard/github/swissarmyhammer/FoundationModelsFileTool && swift test`. Expect zero failures.

## Workflow
- Use `/tdd` — write the failing `FileContext` test first, then implement to make it pass. #filetool-pure-edit