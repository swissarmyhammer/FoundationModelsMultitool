---
assignees:
- claude-code
position_column: todo
position_ordinal: '8180'
title: Mark a runCode call that calls no tools.* verb as a no-op
---
## Problem

SWE-bench run no-otel-1011 (2026-10-11, Multitool a00e883), django__django-13964: while a `tools.code_context.detectProjects` call was pending, the model made 73 no-op runCode calls (`return "waiting placeholder"`, `return null`, `return "end 11"`, `"done 12"`, ...). Only the Router repetition watch stopped it. This is the same loop as task ^cf57dtd. See also ^1dzf1za (the shared pending text).

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

- [ ] `MultiTool.callsNoTool(snippet:)` is public, static and pure.
- [ ] It returns true for `return null`, `return "waiting 3"` and an empty snippet.
- [ ] It returns false for any snippet that calls a `tools.*` verb, also `const t = tools; t.shell.execute(...)` and `tools["shell"]`.
- [ ] Tests cover the two cases. #bug