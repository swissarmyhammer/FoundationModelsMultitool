---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m41hx1mancrvbrrv931v493b
  text: |-
    Research and work done:
    - Checked the code facts before the doc edit: `MultiTool.timeout(from:)` gives `configuration.executionTimeLimit` at depth 0 and `nil` at depth > 0; progress events reset it. `RunBinding.innerCallMount` is `ToolMount(mode: .runToCompletion)` with no timeout. `JSCInterpreter` has only `init()`; its watchdog is a short poll that reads task cancellation. `WebFetcher` sets the URLSession request, resource and `URLRequest` timers to `.infinity`.
    - RED: added `ExamplesTests.removedClockPhrases` and the test `shippedContractDocumentDescribesNoRemovedClock` (README.md and docs/SECURITY.md only; plan.md and eventplan.md stay historical). It failed on docs/SECURITY.md with 5 sightings (wall-clock timer, withTimeLimit, timeLimit:, sandbox creation x2). README.md passed.
    - GREEN: rewrote the "Execution time", "Inner-call time" and "Cancellation" bullets, added a "Web time" bullet (no fetch `timeout` argument, no provider timeout, URLSession timers off), and changed "Live snippets" to name the tool-level timeout.
    - README.md has no stale clock words and no CLI words. Its `defaultInlineSettleGrace` text is current (it is not a work clock). No change to README.md.
    - The suite prints one SwiftPM build message, `warning: missing creator for mutated node` on the mlx-swift_Cmlx bundle. It comes from the build graph of the mlx dependency, not from the code of this package.
  timestamp: 2026-10-03T18:54:54.602192+00:00
- actor: claude-code
  id: 01m41hx6pcr79syd7nehhv908g
  text: |-
    ### implement — changed
    - evidence: 2 files — docs/SECURITY.md, Tests/FoundationModelsMultitoolTests/ExamplesTests.swift. RED: `swift test --filter shippedContractDocumentDescribesNoRemovedClock` failed on docs/SECURITY.md (5 sightings). `swift test --filter 'ExamplesTests|WebDocumentationTests|HardeningTests'`: 20 tests in 3 suites passed. `swift test`: 1810 tests in 151 suites passed. The card rg finds nothing.
    - next: review
  timestamp: 2026-10-03T18:54:59.788294+00:00
depends_on:
- 01M413X82NWGVNF2XKW8V2FV2Z
- 01M413YDNNJSNTFCJEY71CBG70
position_column: doing
position_ordinal: '8180'
title: 'Update docs/SECURITY.md: the snippet ceiling is the tool-level timeout, not a sandbox clock'
---
## What
After `^8v2fv2z`, `JSCInterpreter` has no clock: no CPU-watchdog deadline, no wall-clock timer of the run, and no `JSCInterpreter(timeLimit:)`. After task 01M413YDNNJSNTFCJEY71CBG70, `MultiTool.init` does not re-arm an interpreter with `withTimeLimit(_:)`. The section of `docs/SECURITY.md` about the snippet ceiling still states all of these.

- [x] `docs/SECURITY.md`: rewrite the bullet about the snippet ceiling (it names `JSCInterpreter(timeLimit:)`, "the wall-clock timer of the run", `Interpreter.withTimeLimit(_:)` and "The ceiling is absolute: it is measured from sandbox creation"). State that the one outer timeout of a `runCode` call is the tool-level timeout `MultiTool.timeout(from:)`, from `MultiToolConfiguration.executionTimeLimit`. State that it cancels the run, that the CPU watchdog stops a JS loop at the next poll after the cancellation, and that a `JSCInterpreter` run outside a `MultiTool` ends only on cancellation of its task.
- [x] Check the "Inner-call time" and "Cancellation" bullets beside it for the same stale words ("snippet ceiling above", "measured from sandbox creation", "that same watchdog path").
- [x] Check `README.md` for the same stale words. Leave the historical plan files (`plan.md`, `eventplan.md`, `web.md`) as they are.

## Acceptance Criteria
- [x] `rg -n "JSCInterpreter\(timeLimit|wall-clock timer of the run|withTimeLimit|measured from\s+sandbox creation" docs/SECURITY.md README.md` finds nothing.
- [x] The doc tests (`ExamplesTests`, `WebDocumentationTests`, `HardeningTests`) pass.

## Tests
- [x] `swift test --filter 'ExamplesTests|WebDocumentationTests|HardeningTests'` passes. `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #docs #timeouts