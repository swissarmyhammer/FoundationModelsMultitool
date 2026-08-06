---
assignees:
- claude-code
position_column: todo
position_ordinal: '9180'
title: 'Cancellation semantics ruled: terminate-without-settling — pin it, amend wording, fix false @Guide claims'
---
HUMAN DECISION (plan author, 2026-08-06), resolving the ^az1xs92 AC5 conflict escalated by the orchestrator. This ruling also RETROACTIVELY RATIFIES the ^yahbkg5 cancellation narrowing that a reviewer agent improperly self-cleared (acknowledged process violation — future conflicts must park for a human; this card is the human record).

RULING: `cancel(completionToken)` semantics are **terminate-without-settling** — cancel the backing Swift Tasks and terminate the JSC context WITHOUT settling pending promises. Author-written `.catch()` / `finally {}` in the snippet does NOT run on cancellation. This is deliberate: settling would resume author JS outside any armed watchdog (a cancelled snippet's `finally { while(true){} }` would be unkillable), and it matches platform precedent (terminated Workers do not run `finally`). Literal rejection is REJECTED as a requirement. The wording is amended, not the code.

## What
1. **Amend the spec text** in `eventplan.md` (cancel / Async JavaScript sections): replace "rejects its pending promises" with the terminate-without-settling contract above, stated explicitly including "author `.catch()`/`finally` does not run on cancel; host-side cleanup is the engine's job."
2. **Pin the semantics with a test** in `Tests/FoundationModelsMultitoolTests/`: a snippet that arranges an observable side effect inside `finally {}` (and a `.catch()`) around a pending `tools.*` promise, then is cancelled — assert the side effect did NOT occur, the run terminates, and the terminal outcome is the cancelled one. This makes the skipped-`finally` behavior a contract, not an accident.
3. **Fix the false model-facing text** (the `@Guide`/description strings): current text claims "Progress resets it, so a snippet that keeps reporting keeps running" and that a suspended context "is never force-terminated before its own work clock says so" — both FALSE at the interpreter level (`runStart` is a `let`; `rearm()` re-arms the poll interval, not the limit; snippets parked on `elicit()` or reporting progress can still hit the interpreter cap). Reword to the truth: the ENGINE's elevated-run timeout resets on progress; the INTERPRETER watchdog limit is absolute per snippet. Do NOT make the interpreter watchdog progress-aware — the absolute cap is the intended safety property; fix the words, not the clock.
4. Add a comment on ^az1xs92 and ^yahbkg5 linking to this card as the human adjudication record.

## Acceptance Criteria
- [ ] eventplan.md cancel wording matches shipped terminate-without-settling semantics, explicitly covering skipped `.catch()`/`finally`
- [ ] New test proves author `finally`/`catch` does not run on cancel and the cancelled terminal outcome is recorded
- [ ] No model-facing description/@Guide string claims progress extends the interpreter watchdog or that suspended contexts cannot be force-terminated; the engine-vs-interpreter clock distinction is stated accurately
- [ ] `swift test` green

## Tests
- [ ] The new cancellation-pinning test above
- [ ] Existing cancellation tests (HardeningTests, cancellationCancelsWhileAwaitingAPendingToolCall) still green

## Workflow
- Use `/tdd` — write the pinning test first (it should pass against current behavior — it is a pin, not a bug fix; if it FAILS, stop and park stuck, the ruling's premise is wrong). #phase-1