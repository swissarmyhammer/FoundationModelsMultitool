---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4p63h1yj67aga90xxahbzsv
  text: |-
    Implementation landed.

    - New file `Sources/FoundationModelsMultitool/Invocation/PendingWorkInstruction.swift`: `enum PendingWorkInstruction { static let text }`. It holds the approved text word for word.
    - `MultiTool.collectInstruction`: "The snippet is still running in the background, with completionToken \"<token>\". " + text.
    - `Execute.collectInstruction`: "The command is running in the background, with commandID \"<token>\". To read what it has written so far, call tools.shell.getLines with that commandID. " + text. The getLines pointer stays, because it is the commandID part that this place needs.
    - `Execute.description`: "...continues in the background, and the answer is pending. \(text) In a snippet..."
    - runCode description (`contractText`): "When runCode answers with `pending` true, the snippet is still going. \(text)".
    - `SandboxGlobalError.waitRemoved`: "wait() does not exist. Do not wait for a run inside a snippet. Return the completion token of the run. " + text.
    - Doc comments in MultiTool.swift and MultiTool+Background.swift, README (two places), and test comments no longer say that the model ends its answer. The integration stub `ShellBackgroundReportTests.collectInstruction` is now "This is not the result." (the count does not read it).

    Tests: the old assertions on fixed words now reference `PendingWorkInstruction.text` (InlineSettleGraceTests, RouterSessionMountTests, MultiToolExecutionTests, SandboxGlobalsTests). Two new tests in ShellExecuteTests check that the Execute pending sentence and the Execute description carry the constant. No test pins or bans words.

    Discovery: the `dump validators` file for one .swift path is 754 KB (12098 lines). It is too large to read in one pass.

    Remaining text that says "end the turn" is in developer comments about thrown errors, and one behavior description in ScenarioGrading.swift. None of it goes to the model.
  timestamp: 2026-10-11T19:12:47.166899+00:00
- actor: claude-code
  id: 01m4p63pxfzbdy5j14yz2ck7v4
  text: |-
    ### implement — changed
    - evidence: 15 files. New: Sources/FoundationModelsMultitool/Invocation/PendingWorkInstruction.swift. Changed: Sources/FoundationModelsMultitool/{MultiTool+Background.swift, MultiTool+Description.swift, MultiTool+SandboxGlobals.swift, MultiTool.swift, Capabilities/Shell/Execute.swift}; Tests/FoundationModelsMultitoolTests/{InlineSettleGraceTests.swift, RouterSessionMountTests.swift, MultiToolExecutionTests.swift, SandboxGlobalsTests.swift, ShellExecuteTests.swift}; Tests/Support/ScenarioGrading/ScenarioTools.swift; IntegrationTests/.../{InBandCollectionCanaryTests.swift, ShellBackgroundReportTests.swift}; README.md. RED: 6 tests, 6 issues. GREEN: 6 of 6 pass. `swift test`: 2366 tests in 208 suites pass. `swift build --package-path IntegrationTests --build-tests`: complete, no warning in project sources.
    - next: /review
  timestamp: 2026-10-11T19:12:53.167938+00:00
- actor: claude-code
  id: 01m4p694km48nqdzca6yzztqda
  text: |-
    Coordinator decision applied: `Execute.collectInstruction` no longer points to `tools.shell.getLines`. The pointer conflicted with the shared text ("Do not call a tool to wait or to check"). The sentence is now `The command is running in the background, with commandID "<token>". ` and then `PendingWorkInstruction.text`. Its doc comment now says why there is no getLines pointer. No test read the old pointer. I corrected the doc comment of the ShellExecuteTests test, which named getLines.

    ### implement — changed
    - evidence: 2 files — Sources/FoundationModelsMultitool/Capabilities/Shell/Execute.swift, Tests/FoundationModelsMultitoolTests/ShellExecuteTests.swift. `swift test --filter "ShellExecuteTests|BackgroundSettleGraceTests"`: 39 tests in 2 suites pass, no warnings in project sources.
    - next: /review
  timestamp: 2026-10-11T19:15:51.028986+00:00
position_column: doing
position_ordinal: '80'
title: Use one shared pending text for all background-work places
---
## Problem

SWE-bench run no-otel-1011 (2026-10-11, Multitool a00e883) found a model loop while work is pending:

- django__django-13964: a runCode call of `tools.code_context.detectProjects` went pending. The model then made 73 no-op runCode calls (`return "waiting placeholder"`, `return null`, `return "end 11"`, ...). Only the Router repetition watch stopped it (watchStop finish=repeatedLines).
- django__django-13447: an inner `tools.shell.execute` went pending. The snippet read `s.output` (undefined) and failed. The model sent the same 1006-test command again, and 2 copies ran in parallel.
- This is the same loop as task ^cf57dtd. The sentence "Do not call runCode to wait or to check" did not stop it.

## Decision of the user

There are no turns. Do not tell the model to "end your answer". There is no wait tool. Parallel tool calls must stay free. If there is no other work, the model must do nothing.

## Work

Make one shared constant for the pending text. Use it in these places:

- `MultiTool+Background.swift:52` `collectInstruction(forCompletionToken:)`
- `Capabilities/Shell/Execute.swift:201` (the pending text of a background execute)
- `Capabilities/Shell/Execute.swift:856` (the execute description)
- `MultiTool+Description.swift:102` (the runCode description)
- `MultiTool+SandboxGlobals.swift:792` (remove "Return the completion token and end your answer.")

Keep the completionToken / commandID part that each place needs. The approved text is:

"This is not the result. When the work finishes, the session injects its result into this conversation as a new message. That message starts you working again, so you do not need to wait, to check, or to ask for it. Do not call a tool to wait or to check. If you have other work that does not need this result, do that work now. If no other work can be done until the result comes back, do nothing: write no text and call no tool. When the injected result arrives, continue the task from it."

Do not change a snippet that settles inside inlineSettleGrace. It answers with its own result, and the text does not show.

## Acceptance

- [x] One constant holds the text. All five places use it.
- [x] No text tells the model to "end your answer" or to end a turn.
- [x] Tests pass. #bug