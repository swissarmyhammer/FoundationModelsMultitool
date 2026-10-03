---
assignees:
- claude-code
depends_on:
- 01M413X82NWGVNF2XKW8V2FV2Z
- 01M413YDNNJSNTFCJEY71CBG70
position_column: todo
position_ordinal: '8980'
title: 'Update docs/SECURITY.md: the snippet ceiling is the tool-level timeout, not a sandbox clock'
---
## What
After `^8v2fv2z`, `JSCInterpreter` has no clock: no CPU-watchdog deadline, no wall-clock timer of the run, and no `JSCInterpreter(timeLimit:)`. After task 01M413YDNNJSNTFCJEY71CBG70, `MultiTool.init` does not re-arm an interpreter with `withTimeLimit(_:)`. The section of `docs/SECURITY.md` about the snippet ceiling still states all of these.

- [ ] `docs/SECURITY.md`: rewrite the bullet about the snippet ceiling (it names `JSCInterpreter(timeLimit:)`, "the wall-clock timer of the run", `Interpreter.withTimeLimit(_:)` and "The ceiling is absolute: it is measured from sandbox creation"). State that the one outer timeout of a `runCode` call is the tool-level timeout `MultiTool.timeout(from:)`, from `MultiToolConfiguration.executionTimeLimit`. State that it cancels the run, that the CPU watchdog stops a JS loop at the next poll after the cancellation, and that a `JSCInterpreter` run outside a `MultiTool` ends only on cancellation of its task.
- [ ] Check the "Inner-call time" and "Cancellation" bullets beside it for the same stale words ("snippet ceiling above", "measured from sandbox creation", "that same watchdog path").
- [ ] Check `README.md` for the same stale words. Leave the historical plan files (`plan.md`, `eventplan.md`, `web.md`) as they are.

## Acceptance Criteria
- [ ] `rg -n "JSCInterpreter\(timeLimit|wall-clock timer of the run|withTimeLimit|measured from\s+sandbox creation" docs/SECURITY.md README.md` finds nothing.
- [ ] The doc tests (`ExamplesTests`, `WebDocumentationTests`, `HardeningTests`) pass.

## Tests
- [ ] `swift test --filter 'ExamplesTests|WebDocumentationTests|HardeningTests'` passes. `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #timeouts #docs