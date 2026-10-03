---
assignees:
- claude-code
depends_on:
- 01M413X82NWGVNF2XKW8V2FV2Z
position_column: todo
position_ordinal: '8280'
title: Remove Interpreter.withTimeLimit and the re-arm in MultiTool.init
---
## What
After `^8v2fv2z`, `JSCInterpreter.withTimeLimit(_:)` returns `self`, and the sandbox has no clock. The protocol requirement and the re-arm are then dead code. Each path has one outer, tool-level timeout: for `runCode`, this is `MultiTool.timeout(from:)`.

- [ ] `Sources/FoundationModelsMultitool/Interpreter/Interpreter.swift`: remove the `withTimeLimit(_:)` requirement and its doc. Update the protocol doc so that it says a conformer stops a run only on cancellation of the calling `Task`.
- [ ] `Sources/FoundationModelsMultitool/Interpreter/JSCInterpreter.swift`: remove `withTimeLimit(_:)` and the init doc text about the `MultiTool` re-arm.
- [ ] `Sources/FoundationModelsMultitool/MultiTool.swift:436`: `self.interpreter = interpreter ?? JSCInterpreter()`. Remove the comment about the re-arm and update the `interpreter:` parameter doc (near line 405).
- [ ] `Sources/FoundationModelsMultitool/MultiToolConfiguration.swift`: rewrite the doc of `executionTimeLimit`. It is the one tool-level clock of `runCode`. Progress events reset it. Remove the text about the sandbox watchdog, the "absolute cap", the injected interpreter re-arm, and the "5 seconds" stock limit.
- [ ] `Sources/FoundationModelsMultitool/MultiTool+Background.swift`: rewrite the doc of `timeout(from:)` and `mount` the same way.

## Acceptance Criteria
- [ ] `rg "withTimeLimit" Sources Tests` finds nothing.
- [ ] `rg -i "absolute cap|second clock|re-arm" Sources/FoundationModelsMultitool/MultiToolConfiguration.swift Sources/FoundationModelsMultitool/MultiTool+Background.swift` finds nothing.
- [ ] The build has no new warnings.

## Tests
- [ ] The tool-level timeout tests of `^e2xvhtk` pass with no change.
- [ ] `swift build` and `swift test` pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #timeouts #tech-debt