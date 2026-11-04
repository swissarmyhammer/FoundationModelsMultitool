---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m6ha3v784rmsg0t0qjzfcx2z
  text: |-
    Shape agreed with the Extras session (their task 01M6HA3B670G61TZ115SGX9DAA). Nothing is built yet.
    Option 3: the tool returns its output string as today. Before it returns, it calls ToolContext.current?.reportFailure(value: .int(exitCode)). Extras then records outcome failed, and the detail stays the output text. OperationEvent gets an optional field value. OperationOutcome does not change. A stop, a timeout or a cancel still wins over a reported failure.
    Multitool change: one call in ShellRunner.finalizeResult on a nonzero exit. No signature change.
    Precondition: make no Multitool code change until Extras says its task is done. Then check the Extras origin/main myself.
  timestamp: 2026-11-03T18:18:03.368675+00:00
- actor: claude-code
  id: 01m6haagh4820pnvg6t3f5jeaw
  text: 'The user decided: every nonzero exit reports failed, grep exit 1 included. No allowlist and no per-command special case. The exit code goes in the value as int n, so a caller or hook can treat grep exit 1 as no match. Code mode on a script error is still open with the user (A: no change, B: failed with the error text). Still blocked on the Extras done message.'
  timestamp: 2026-11-03T18:21:41.796716+00:00
- actor: claude-code
  id: 01m6hab0a3pg8nrzv4x6vd74gr
  text: 'The user decided code mode: option B. A code mode script failure reports failed. The model still gets the same repairable error text as output. In MultiTool.runSnippet, in the InterpreterError branch, the run also calls ToolContext.current?.reportFailure(value: string of the error text). A syntax error that a repaired snippet or the Python fallback then fixes reports the outcome of the second run, so the call must come after those two paths and only when they do not apply. A nested run (enclosingRun not nil) needs a check: decide whether the inner failure reports on the inner context or not. A test must cover each path. Wait for the Extras done message before code.'
  timestamp: 2026-11-03T18:21:57.955502+00:00
- actor: claude-code
  id: 01m6hj7c9f7wfhvjb2k0cttq24
  text: |-
    ### review - clean
    - scope: review sha daabfa71~1..daabfa71 (4 files)
    - evidence: 0 findings, 0 confirmed, 2 refuted
    - next: task moved to done
  timestamp: 2026-11-03T20:39:47.759533+00:00
position_column: done
position_ordinal: ffffffe580
title: 'Shell tool: a nonzero exit gives a failed outcome that carries the exit code'
---
The user decided: the shell tool must give a failed outcome on a nonzero exit. The failure must carry the exit code as a value.

Today: ShellRunner.finalizeResult records a nonzero exit as status completed with exitCode, and the verb returns a normal string. Execute.outcome(of:in:) gives a failed outcome on the terminal OperationEvent only. FoundationModelsExtras ToolRun.outcomeAndDetail gives a failed outcome only when the tool throws, so a caller cannot see the failure in the return path.

Work:
- On a nonzero exit, end the run as failed. Keep the output and the exit code.
- This needs a way in FoundationModelsExtras for a failure to carry a value. The shape is not agreed. Agree the shape with the session foundationmodelsextras-01 before any code.
- The ACP agent session (foundationmodelsacpagent-9b) waits for this. Its CI uses Multitool main, so push an API-compatible change first.

Open questions:
- Grep exit 1 is not always a failure. Decide if a command may declare exit codes that mean success.
- Code mode on a script error: the user did not decide yet. Today MultiTool.runSnippet catches InterpreterError and returns repairable-error text, so the outcome is succeeded. Make no change until the user decides.

No test may depend on machine speed.