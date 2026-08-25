---
assignees:
- claude-code
depends_on:
- 01M0WWST94MBZF5JD463GZC6AN
position_column: todo
position_ordinal: '9080'
title: Prove the files capability end to end through runCode
---
## What
Prove the six verbs work as one session through the code-mode surface, in the pattern of the Shell end-to-end tests (`ShellExecuteTests.swift`, `SiblingToolPathTests.swift`) and of the FileTool cross-op flow tests (`/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Tests/FileToolIntegrationTests/CrossOpFlowTests.swift`).

- New file: `Tests/FoundationModelsMultitoolTests/FilesCrossOpFlowTests.swift`

The flows to prove, each through a `runCode` snippet against a temporary root:
1. Write → read: a snippet writes a file and reads it back. The content agrees.
2. Glob → grep: a snippet globs the root and greps a match in the found files.
3. Read (hashline) → edit: a snippet reads a file in the hashline format and edits it with an anchor from that read.
4. Patch → read: a snippet applies a patch and reads the changed file.
5. Corrective in-band: a snippet asks for a path outside the root. The snippet receives a corrective result inside JS, and the run does not throw. The snippet corrects the call in the same run.
6. Parallel calls: `Promise.all` over two reads settles both (eventplan.md § "Async JavaScript").

## Acceptance Criteria
- [ ] Each flow runs through the JSC interpreter and `ToolInvoker`, not through direct engine calls.
- [ ] The intermediate-value claim is asserted through the invocation ledger, in the pattern of `ToolReturnLedgerTests.swift`: the ledger (`Sources/FoundationModelsMultitool/Invocation/ToolReturnLedger.swift`) or `CallTrace` shows each inner call ran, and the test asserts the file contents and the returned result carry only the final value.
- [ ] `swift test` passes with no new warnings.

## Tests
- [ ] `swift test --filter FilesCrossOpFlowTests` passes.

## Workflow
- Write the tests. Change no production code. If a flow fails, file the defect against the task that owns the failing verb.