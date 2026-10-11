---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4p74m5dawgtp70byyrtd8tm
  text: |-
    Research done.
    - `MultiTool` is a public struct in `Sources/FoundationModelsMultitool/MultiTool.swift`. Each topic has its own extension file `MultiTool+<Topic>.swift`. The new check goes in a new file `MultiTool+NoOpSnippet.swift`.
    - The interpreter installs `tools` as a global object of the JSContext. Thus a snippet can reach it through a computed name (for example `globalThis["to" + "ols"]`). A static text check cannot see that form. The agreed design accepts this limit: the check looks for the identifier only.
    - JavaScript lets an identifier hold a `\u` escape (`tools` is `tools`). The check returns false for any snippet with a `\u` escape, so this form can not give a wrong true.
    - Identifier characters for the word boundary are ASCII letters, digits, `_` and `$` only. Any other character counts as a boundary. This can only give more false results, which is safe.
  timestamp: 2026-10-11T19:30:51.693121+00:00
- actor: claude-code
  id: 01m4p7qymshk0mtrahxhvm55xs
  text: |-
    ### implement — changed
    - evidence: 2 new files — Sources/FoundationModelsMultitool/MultiTool+NoOpSnippet.swift, Tests/FoundationModelsMultitoolTests/NoOpSnippetTests.swift. RED: build failed with "type 'MultiTool' has no member 'callsNoTool'". GREEN: `swift test --filter NoOpSnippetTests` 4 tests (22 cases) pass. Full `swift test`: 2370 tests in 209 suites pass, 0 failures. swiftlint on the two files: clean.
    - notes: The check works on UTF-8 bytes. It returns false for any `\u` escape, because `tools` is the identifier `tools`. The default swift-format config of the toolchain asks for 2-space indent and trailing commas; the project has no `.swift-format` file and its swiftlint config bans trailing commas, so the files follow swiftlint and the 4-space code of the project. The only build warning ("missing creator for mutated node" on the mlx-swift_Cmlx bundle) comes from the SwiftPM build system for a dependency. It was present before this change.
    - next: review.
  timestamp: 2026-10-11T19:41:25.017315+00:00
- actor: claude-code
  id: 01m4p7r4j20bd0aemjqqczy8jt
  text: 'Correction to the two comments above: the tool input decoded the escape in the example. The example is the letter t, then a backslash-u escape with the hex code 006f (the letter o), then the letters "ols". JavaScript reads that text as the identifier `tools`. The test `unicodeEscapeIsNeverANoOp` holds the real text.'
  timestamp: 2026-10-11T19:41:31.074605+00:00
- actor: claude-code
  id: 01m4p8b8n1p2h18h3vajc8w5sw
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (4c35b7f). 0 findings, 0 confirmed, 0 refuted. 7 checks done, 0 failed. 2 source files reviewed. 4 .kanban files not reviewed (.reviewignore).
    - next: The task is in done. Send the commit sha 4c35b7f to ACPAgent (foundationmodelsacpagent-36).
  timestamp: 2026-10-11T19:51:57.857461+00:00
- actor: claude-code
  id: 01m4p8bnaa4xy7t2jb8f8yz3ew
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 2 new files
    - test: green — swift test, 2370 passed, 0 skipped; IntegrationTests build complete
    - commit: 4c35b7f
    - review: clean — 0 findings
  timestamp: 2026-10-11T19:52:10.826036+00:00
position_column: done
position_ordinal: ffffd980
title: Mark a runCode call that calls no tools.* verb as a no-op
---
## Problem

SWE-bench run no-otel-1011 (2026-10-11, Multitool a00e883), django__django-13964: while a `tools.code_context.detectProjects` call was pending, the model made 73 no-op runCode calls (`return "waiting placeholder"`, `return null`, `return "end 11"`, `"done 12"`, ...). Only the Router repetition watch stopped it. This is the same loop as task ^cf57dtd. See also ^1dzf1za (the shared pending text).

More evidence (6 instances of the same run): 5 of 6 instances have runCode calls that call no `tools.*` verb. Counts: 13447=1, 13710=3, 13925=2, 13933=2, 13964=73, 14016=33. The forms include `return "stop";`, `return 1;`, a bare `1`, `return "waiting for 01M4P046...";` and `await new Promise(() => {});`. The last form calls no tool and never settles. If it runs, it goes pending itself and holds a run until the execution time limit.

## Agreed design (with Router session foundationmodelsrouter-17, Router task ^rw72f4j)

Router must know that a call is a no-op BEFORE it runs the call. Thus the mark is a static check of the snippet, not a field in the result.

- Add `public static func callsNoTool(snippet: String) -> Bool` on `MultiTool` (module FoundationModelsMultitool).
- Input: the raw snippet text (`RunCodeArguments.snippet`).
- Output: true only when the snippet does not contain the identifier `tools` (a whole-word match). The check is strict: a snippet that can call a `tools.*` verb must never return true. A no-op snippet that has the word "tools" (for example in a string) can return false. That is safe.
- The function is pure. It does not run the snippet.
- Router gets an injected check `isNoOpToolCall(toolName, arguments)`. ACPAgent (foundationmodelsacpagent-36) wires `name == "runCode" && MultiTool.callsNoTool(snippet:)` into it. While an operation of the session is pending, Router stops the generation on a no-op call.
- After the commit is on main, the orchestrator sends the commit sha to ACPAgent (foundationmodelsacpagent-36). Router does not need it.

## Constraints (decision of the user)

- There are no turns and there is no wait tool.
- Parallel tool calls must stay free.
- The check only gives information. It does not block or change a call in the Multitool.

## Acceptance

- [x] `MultiTool.callsNoTool(snippet:)` is public, static and pure.
- [x] It returns true for each of these snippets: `return null`, `return "waiting 3"`, an empty snippet, `return "stop";`, `return 1;`, a bare `1`, `return "waiting for 01M4P046...";` and `await new Promise(() => {});`.
- [x] It returns false for any snippet that calls a `tools.*` verb, also `const t = tools; t.shell.execute(...)` and `tools["shell"]`.
- [x] Tests cover the two cases. The test for `await new Promise(() => {});` does not run the snippet. #bug