---
assignees:
- claude-code
depends_on:
- 01M1H2RZYD71QYG972YGKQ122C
position_column: todo
position_ordinal: '8480'
title: Add defaultWorkingDirectory to ShellCapability.init and withShell
---
## What
Ask 6, part 2 (UPSTREAM_ASKS.md). Expose the runner default on the public composition, so a host gives the session root one time.

- `Sources/FoundationModelsMultitool/Capabilities/Shell/ShellCapability.swift`: add a fourth parameter `defaultWorkingDirectory: URL? = nil` to `public init(storeDirectory:sandbox:outputChunkStream:)`. `ShellRunner` is a struct, so build it as `var runner = ShellRunner(state:outputChunkStream:sandbox:)` and then set `runner.defaultWorkingDirectory = defaultWorkingDirectory?.path`. Document: the directory a `tools.shell.execute` call runs in when it omits `workingDirectory`; the default, `nil`, keeps the current directory of this process; a host with a session root passes that root. Update the doc comment that says "the same three arguments" to four.
- `Sources/FoundationModelsMultitool/Surface/MultiToolBuilder.swift`: add the same parameter to `withShell(storeDirectory:sandbox:outputChunkStream:)` and pass it through. Update the parameter list in its doc comment, and the `MultiToolBuilderError` header comment (line 13) that spells the `withShell` signature.

The model-facing text and the sandbox scenario are the next task ("Correct the shell working-directory text and prove the Ask 6 scenario").

## Acceptance Criteria
- [ ] `ShellCapability(storeDirectory:defaultWorkingDirectory:)` gives an `Execute` verb whose `runner.defaultWorkingDirectory` is the `path` of the URL.
- [ ] `ShellCapability(storeDirectory:)` gives an `Execute` verb whose `runner.defaultWorkingDirectory` is `nil`.
- [ ] `MultiTool.Builder().withShell(storeDirectory:defaultWorkingDirectory:).buildRegistry()` renders the same three verbs, and `registry.tools["shell.execute"] as? Execute` carries the default.
- [ ] Every existing shell test stays green.

## Tests
- [ ] Add to `Tests/FoundationModelsMultitoolTests/ShellCapabilityTests.swift`: `theDefaultWorkingDirectoryReachesTheRunner`, `theDefaultWorkingDirectoryIsNilWhenNotGiven`, `withShellPassesTheDefaultWorkingDirectoryThrough`. Find the verb by type as `FilesCapabilityTests.verb(_:in:)` does.
- [ ] Run `swift test --filter "ShellCapabilityTests|ShellExecuteTests|ShellRunnerTests"` and expect every test to pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #ask-6 #upstream-asks