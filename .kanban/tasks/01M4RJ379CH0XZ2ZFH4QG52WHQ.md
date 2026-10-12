---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4rje430dn55d0p4rzvrvk26
  text: |-
    Research:
    - A pending inner call gives the snippet an object `{pending: true, completionToken, next}` (SnippetOutput.swift). `tools.shell.execute` adds `commandID` (Execute.swift, SnippetOutputShaping).
    - Each `tools.*` binding is wrapped in `MultiTool.recording(_:into:noting:holding:)` with per-run records (ToolReturnLedger, LostRunRecord, InFlightInnerCalls). A new per-run record of pending inner calls fits this pattern.
    - `runSnippet` renders the result with `ResultRenderer.render(_:limits:notice:)`. The inline answer and the background mail both come from this one rendered string, so one notice covers the inline settle and the background settle.
    - Conflict found: ToolReturnLedger records the strings of a pending object. A snippet that does not return the pending object then gets the "call runCode again and return them" notice. That text tells the model to run the call again. The fix must keep a pending value out of the ledger.
    - Nested `tools.runCode` (depth > 0) gets no notice (same rule as the ledger notice), because a snippet reads that text.
    - Test pattern: BackgroundSettleGraceTests (real Router session through makeMailProbeSession, real `sleep` commands, ShellState.listCommands gives the commandID).
  timestamp: 2026-10-12T17:26:46.112850+00:00
- actor: claude-code
  id: 01m4rjyta11h5ge8sth7yqvk5z
  text: |-
    Implementation landed (not committed):
    - New `Invocation/PendingInnerCalls.swift`: a per-run record (Mutex, same pattern as ToolReturnLedger). Each `tools.*` binding is wrapped with it. When a binding gives a pending object (`{pending: true, completionToken}`), the record notes the path, tool, op, and commandID (shell) or completionToken. Its notice lists each call, then "Do not run these calls again." and `PendingRunEnvelope.pendingWorkInstruction`.
    - `MultiTool.runSnippet` puts the notice last on a success render (after the ledger notice), and also after the repair directive on a failed snippet (evidence 2: a snippet that read `s.output.slice` on a pending object). Only at depth 0, same rule as the ledger notice.
    - `ToolReturnLedger.recording` does not record a pending object. Before this, a snippet that did not return the pending object could get "call runCode again and return them", which tells the model to run the call again.
    - `InterpreterValue.pendingCompletionToken` (SnippetOutput.swift) is the one reading of a pending object. `LiveTool` got `path` and `callName`. The wrap takes one `InnerCallRecords` struct in place of four arguments.
    - plan.md "Output" section describes the second notice.
    - Discovery: the background mail of a runCode run already shows the inner execute "running" event line, but nothing tied it to the snippet result. A JSON-quoted result in mail escapes quotes, so tests check the path, the id and the shared text, not the quoted form.
    - Not done here, new task ^tshp2t9: a nested `tools.runCode` that leaves a pending call is not named in the outer result.
    - Tests: 3 new tests in BackgroundSettleGraceTests (inline settle, failed snippet, background settle), 1 in ToolReturnLedgerTests. Each was seen RED first.
  timestamp: 2026-10-12T17:35:53.153059+00:00
- actor: claude-code
  id: 01m4rjyxn42gdf1z8xpdvs9mft
  text: |-
    ### implement — changed
    - evidence: 7 files — Sources/FoundationModelsMultitool/Invocation/PendingInnerCalls.swift (new), Sources/FoundationModelsMultitool/MultiTool.swift, Sources/FoundationModelsMultitool/Invocation/ToolReturnLedger.swift, Sources/FoundationModelsMultitool/Invocation/SnippetOutput.swift, Tests/FoundationModelsMultitoolTests/BackgroundSettleGraceTests.swift, Tests/FoundationModelsMultitoolTests/ToolReturnLedgerTests.swift, plan.md. `swift test`: 2374 tests in 209 suites passed, 0 failed. One build-system line "warning: missing creator for mutated node" for the mlx-swift_Cmlx.bundle comes from the build graph, not from the source.
    - next: /review (task stays in doing). Follow-up task ^tshp2t9 for nested runCode.
  timestamp: 2026-10-12T17:35:56.580643+00:00
- actor: claude-code
  id: 01m4rk11fbdm6nsm6caz3642h0
  text: |-
    ### test — green
    - evidence: swift test — 2374 tests in 209 suites passed, 0 failed, 0 skipped. No compiler warning from the package source.
    - note: one build-tool message only: "missing creator for mutated node" for the mlx-swift_Cmlx bundle. It comes from a dependency bundle, not from the source of this task.
    - next: review.
  timestamp: 2026-10-12T17:37:06.027522+00:00
- actor: claude-code
  id: 01m4rk1mqkqgqynxxctt43rga2
  text: |-
    ### commit — changed
    - evidence: ea2b675 feat(runcode): name pending inner calls in the result when a snippet ends
    - next: review
  timestamp: 2026-10-12T17:37:25.747339+00:00
- actor: claude-code
  id: 01m4rk662sqsrz6q6nbfpvwdht
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (baa22e1); 1 finding (1 confirmed, 1 refuted) — Tests/FoundationModelsMultitoolTests/BackgroundSettleGraceTests.swift:86 (reuse/reuse). The commit renames no file.
    - next: implement the open finding in the Review Findings section; the task stays in review.
  timestamp: 2026-10-12T17:39:54.585146+00:00
- actor: claude-code
  id: 01m4rk6k0w3wyeenynn629ct35
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 7 files
    - test: green — swift test, 2374 passed, 0 failed
    - commit: baa22e1
    - review: findings — Tests/FoundationModelsMultitoolTests/BackgroundSettleGraceTests.swift:86
  timestamp: 2026-10-12T17:40:07.836702+00:00
- actor: claude-code
  id: 01m4rkbx5ktpwmhep4rg6688b2
  text: |-
    Finding fixed (reuse/reuse, BackgroundSettleGraceTests.swift:86):
    - `shellRunCode(grace:extraTools:)` is now the one construction path. It takes `extraTools: [any Tool] = []` and passes them to `MultiTool.Builder.addTools`. It returns `(runCode: MultiTool, state: ShellState)`, so the store comes from the same `shellVerbs()` call that the registry uses.
    - `pendingProbeRunCode()` is now one call: `shellRunCode(grace: shortGrace, extraTools: [pause tool])`.
    - The three other callers read `.runCode`.
    - No other registry or configuration build is left in the file. The top-level tests use `shellVerbs()` only and mount `verbs.execute` directly; they build no MultiTool.
    - Why the tuple return: a default argument cannot call the throwing `shellVerbs()`, so a separate `verbs:` parameter would put the build back in each caller.
  timestamp: 2026-10-12T17:43:02.067918+00:00
- actor: claude-code
  id: 01m4rkbzbwe0831neec55p7gyc
  text: |-
    ### implement — changed
    - evidence: 1 file — Tests/FoundationModelsMultitoolTests/BackgroundSettleGraceTests.swift. `swift test --filter BackgroundSettleGraceTests`: 10 tests in 1 suite passed. `swift test`: 2374 tests in 209 suites passed, 0 failed. The only warning is the build-graph line "missing creator for mutated node" for the mlx-swift_Cmlx.bundle dependency, not the source. Not committed.
    - next: /test, then /review (task stays in doing).
  timestamp: 2026-10-12T17:43:04.316765+00:00
- actor: claude-code
  id: 01m4rkjsz0jcw92y0zt7qvbfx5
  text: |-
    ### test — green
    - evidence: `swift package update`, then `swift test` — 2374 tests in 209 suites passed, 0 failed, 0 skipped. The first run had 3 compiler warnings in `Sources/FoundationModelsMultitool/Diagnostics/MultitoolTelemetry+Tracing.swift`: 'ServiceContext' is deprecated, renamed to 'InstrumentationContext'. The update moved swift-distributed-tracing to 1.6.0. I renamed the type, the `Scope` property (now `instrumentationContext`) and the doc comments. The final full run has 0 source warnings. The only warning left is the SwiftPM tool message "missing creator for mutated node" for the mlx bundle. It is not from the source.
    - next: review. The work is not committed. The change in BackgroundSettleGraceTests.swift passes.
  timestamp: 2026-10-12T17:46:48.160556+00:00
- actor: claude-code
  id: 01m4rkkn9ns2yvbh4mnwth96nc
  text: |-
    ### commit — changed
    - evidence: 41f3cb5 refactor(test): share one shellRunCode helper in the settle grace tests; 9c9567f fix(telemetry): use InstrumentationContext in place of ServiceContext
    - next: kanban state is in a third commit. Nothing is pushed.
  timestamp: 2026-10-12T17:47:16.149341+00:00
position_column: doing
position_ordinal: '80'
title: Name the pending inner calls in the runCode result when a snippet ends
---
## Problem

A runCode snippet can end while an inner call that it started is still pending. The runCode result does not tell the model about that call. The model thinks that the call failed or stopped, and it starts the same call again.

Evidence (requested by the FoundationModelsACPAgent session; transcripts are in that repo):

- SWE-bench run noop-stop-1012 (2026-10-12, Multitool e57ddf8), `bench/preds.noop-stop-1012.transcripts/django__django-13447/`:
  - seq 298: the snippet called `tools.files.grep(...)`, then `const r = await tools.shell.execute({ command: "python tests/runtests.py ..." })`. It returned only `{ remaining: g... }` (the grep result).
  - The inner execute (commandID 01M4R5XA1ESMK7EP2ZP3ZR7AVF) went pending (row 154). The snippet completed with `{"remaining":[...]}` (row 155). The command completed later (row 157).
  - seq 301 reasoning: "maybe the shell command is pending ... re-run". seq 302: the model ran the same test command again.
- SWE-bench run no-otel-1011, django__django-13447 seq 428-432: the same gap. The snippet read `s.output.slice` on the pending object and failed. The model started the same 1006-test command again, and 2 copies ran in parallel.

## Decision of the user (from ^1dzf1za)

There are no turns. The session injects the result of pending work as a new message, and that message starts the model working again. If no other work can be done, the model does nothing. There is no wait tool.

## Work

When a snippet settles (inline or in the background) while one or more of its inner calls are still pending, the runCode result must:

- Name each pending inner call: the tool, the op, and the commandID or completionToken.
- Say, with the shared pending-work text (`PendingRunEnvelope.pendingWorkInstruction`), that the result of each call will be injected as a new message, so the model must not run the call again.

This applies also when the snippet return value does not hold the pending object.

Places to start: `MultiTool+Background.swift`, `MultiTool.swift`, `Invocation/RunBinding.swift`, `MultiTool+SandboxGlobals.swift`.

## Acceptance

- [x] When a snippet ends with pending inner calls, the runCode result names each pending call (tool, op, commandID / completionToken).
- [x] The result uses the shared pending-work text. No text tells the model to end its answer or to wait.
- [x] This works for an inline settle and for a background settle.
- [x] New test: a snippet starts a long inner execute, does not return it, and ends. The result names the pending call.
- [x] Tests pass.


## Review Findings (2026-10-12 12:37)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 6 file(s) reviewed, 5 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

> 1 file(s) not reviewed — no validator matched:
> - `plan.md` — no validator matches this file

- [x] `Tests/FoundationModelsMultitoolTests/BackgroundSettleGraceTests.swift:86` `reuse/reuse` — `pendingProbeRunCode()` repeats the registry and configuration build of the existing `shellRunCode(grace:)` helper, with one extra tool added and a fixed grace. Two helpers now carry the same construction steps, and a change to one must be made in both. Give `shellRunCode` an optional `extraTools` parameter, for example `shellRunCode(grace: TimeInterval? = nil, extraTools: [any Tool] = [])`, and call it from `pendingProbeRunCode()`. That keeps one construction path. Keep the state return of `pendingProbeRunCode` by reading it from `shellVerbs()` separately, or return the verbs from the shared helper. #bug