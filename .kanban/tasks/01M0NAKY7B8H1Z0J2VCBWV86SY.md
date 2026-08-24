---
assignees:
- claude-code
depends_on:
- 01M0NAK9M8RG58Q7BTTWJDYXZ3
position_column: todo
position_ordinal: 8b80
title: Add the tools.shell.execute verb
---
## What

eventplan.md § "Registration of capabilities: noun/verb" fixes the layout: one
folder for each noun, and one file for each verb. The file holds the
`@Generable` Arguments, the Output, the handler that reads
`ToolContext.current`, the doc comment, and one example snippet.

- Create
  `Sources/FoundationModelsMultitool/Capabilities/Shell/Execute.swift`.
- `struct Execute: Tool` with `name = "execute"`. The path is
  `tools.shell.execute`, and the journal `op` is `"execute shell"`.
- Arguments come from
  `../FoundationModelsShelltool/Sources/ShellTool/Operations/ExecuteCommand.swift`:
  the command, the working directory, the environment, the timeout, and the
  `wait` detach flag.
- eventplan.md § "The constraint boundary": *"A capability that wants detach
  semantics declares it as a usual argument (shell's `wait`). The capability
  then returns the run's identifier for the builtins."* Keep `wait` as an
  ordinary argument. The verb itself never elevates.
- The handler:
  - Reads `ToolContext.current` one time, at operation start. It captures the
    context into the object that continues after the call. eventplan.md §
    "The ambient context" makes this rule mandatory.
  - Mints nothing. It uses the run's `completionToken` from the context as the
    `commandID`.
  - Asks `ShellPolicy`. An `ask` decision goes through the elicitation task.
  - **Parks the run in the session mailbox** when the command detaches. It
    parks with `RunKind.process`, with the run's settling task, and with the
    `killpg(SIGKILL)` canceler that the `ShellRunner` task supplies. This is
    the one place that parks a shell run. The session-end sweep then reaches
    it.
  - Posts a `progress` event as output arrives, and one terminal event at the
    end.
  - Returns the output tail plus the run identifier, so that the model knows
    how to get more.
- The doc comment carries one runnable example snippet. `findAPIs` serves that
  snippet.

## Acceptance Criteria

- [ ] `tools.shell.execute` renders with an `@example` line that runs as
      written.
- [ ] A short command returns its output inline.
- [ ] A command started with `wait: false` returns the run identifier, and the
      run continues.
- [ ] A detached command is parked in the session mailbox with
      `RunKind.process` and with the `killpg` canceler.
- [ ] `ToolContext.parkedRuns()` lists the detached run under its completion
      token.
- [ ] The `commandID` of the run, its event `correlationID`, and its
      `completionToken` are the same string.
- [ ] The handler reads `ToolContext.current` one time, at start.
- [ ] Exactly one terminal event is posted for each run.

## Tests

- [ ] New `Tests/FoundationModelsMultitoolTests/ShellExecuteTests.swift`,
      ported from
      `../FoundationModelsShelltool/Tests/ShellToolTests/ExecuteCommandTests.swift`.
- [ ] A test asserts the three identifiers are one string.
- [ ] A test with a recording sink asserts exactly one terminal event, and one
      or more `progress` events before it.
- [ ] A test asserts a `wait: false` call returns the identifier and does not
      block.
- [ ] A test asserts the detached run appears in `ToolContext.parkedRuns()`
      with `RunKind.process`.
- [ ] A test calls `ToolContext.cancel(completionToken:)` on the detached run
      and asserts it reports `.reported(.stopped)`.
- [ ] `swift test --filter ShellExecute` passes.
- [ ] `swift test` passes with no new failure and no new warning.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #phase-2 #eventplan