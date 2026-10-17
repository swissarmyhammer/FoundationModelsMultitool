---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m53y4z4qfd5nfbwna780c4dh
  text: |-
    Research: MCPServer.answerElicitation(parameters:generation:) did the URL check with `URL(string:)` only. "foo", "javascript:x" and "https:///no-host" all give a URL from `URL(string:)`, thus each went on to resolve(): to the bound run (the run plane posted the question and waited), or to the host handler. Fetch.httpURL(_:) is internal and reachable from the MCP layer.

    Test design (Rule T1): the run case cannot wait only for the end of the call, because on the old code the run waits for an answer for ever. Thus the test helper runGotTheQuestion(of:on:) uses a task group: one child waits for the end of the call, one child waits for the elicitation event of the run (CollectingTranscriptRecorder.waitUntil, which ends on cancel). When the event comes first, the helper declines the question through the session, thus the call ends also then. The handler case uses a HandlerProbe that declines at once, thus it ends on both code versions.

    RED: 12 issues on the old code (for each of the 3 urls: no reason in `_meta` and 1 handler call; the run got the question and no reason). GREEN: the guard now uses Fetch.httpURL(url.url). An extra test proves that "https://example.com/verify" and "HTTPS://example.com/verify" still go on to the handler (scheme not case-sensitive). The old test of the empty url now uses the new helper connected(askingFor:elicitationHandler:).
  timestamp: 2026-10-17T03:23:07.799572+00:00
- actor: claude-code
  id: 01m53y52796fh5x6gxx5q3vm2x
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsMultitool/Capabilities/MCP/MCPServer+Elicitation.swift (guard uses Fetch.httpURL, header and doc text), Sources/FoundationModelsMultitool/Capabilities/Web/Fetch.swift (doc of httpURL names the new caller), Tests/FoundationModelsMultitoolTests/MCPElicitationTests.swift (3 new parameterized tests, 2 helpers, 1 helper for the connect). RED: filtered run, exit 1, 12 issues. GREEN: filtered run, exit 0. Full `swift test` one time: exit 0, "Test run with 2443 tests in 211 suites passed", XCTest 0 tests 0 failures. The stash "T1 nvxckvr" is not touched.
    - next: /review
  timestamp: 2026-10-17T03:23:10.953616+00:00
- actor: claude-code
  id: 01m53y6wbvw0wpfvdsm1c5cn2q
  text: |-
    ### test - green
    - command: swift test (one run)
    - exit code: 0
    - Swift Testing summary: Test run with 2443 tests in 211 suites passed after 4.293 seconds.
    - failures: none. Skipped tests: none. Compiler warnings: none.
    - note: the build system printed one message, "missing creator for mutated node" for the mlx-swift_Cmlx.bundle. It is not a compiler warning and it comes from a dependency.
    - next: review.
  timestamp: 2026-10-17T03:24:10.491145+00:00
- actor: claude-code
  id: 01m53y7secw102seqgbz2q7ece
  text: |-
    ### commit - changed
    - evidence: commit "fix(mcp): decline an MCP URL question whose url is not an absolute http or https URL" (sha is in the git log; the comment ships in the same commit)
    - scope: MCPServer+Elicitation.swift, Fetch.swift (doc only), MCPElicitationTests.swift, and the .kanban files
    - next: review
  timestamp: 2026-10-17T03:24:40.268954+00:00
- actor: claude-code
  id: 01m53yf4t04g1fxgszq6y7fv4e
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (commit 204414a). 0 findings, 0 confirmed, 1 refuted. 3 files reviewed. 8 .kanban/ files not reviewed (.reviewignore).
    - next: The task has no open findings. The task is in done.
  timestamp: 2026-10-17T03:28:41.280288+00:00
- actor: claude-code
  id: 01m53yfheqnqzpwcnb4v2sqa8e
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 3 files (the server URL-mode guard uses Fetch.httpURL; decline with invalidURLReason)
    - test: green — swift test, exit 0, 2443 passed, 0 failed, 0 skipped
    - commit: 204414a
    - review: clean — 0 findings
  timestamp: 2026-10-17T03:28:54.231412+00:00
position_column: done
position_ordinal: ffffff9080
title: Decline an MCP server URL-mode question whose url is not an absolute http or https URL
---
Found on ^c9nevn0 (group D (a)). The MCP server URL-mode path in MCPServer+Elicitation.swift checks only `URL(string: url.url)` and declines with invalidURLReason only when that gives nil. Thus a server request with url "foo" or "javascript:x" goes on to the host.

Do: use the same rule as the elicit() url check (Fetch.httpURL(_:): an absolute http or https URL with a host) for the server URL-mode request, and decline with invalidURLReason on `_meta.reason` when the URL does not obey it.

The fix starts with a fixed-order test that fails on the current code (RED): a scripted MCP server sends a URL-mode question with "foo" and with "javascript:x"; the result on the wire is a decline with invalidURLReason, and the host gets no request. Rule T1. No time limit, sleep, poll or retry. One full run. #elicitation-fixes