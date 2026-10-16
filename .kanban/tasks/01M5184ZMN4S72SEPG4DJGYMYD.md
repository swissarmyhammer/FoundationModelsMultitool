---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m522ga86r42zps2na5epcy1p
  text: |-
    Research (implement step):
    - callingContext() in MCPServer+Elicitation.swift gives a context only when inFlightCalls.count == 1.
    - Each call sends _meta.progressToken = requestID.description; MCPServer.requestID(of:) maps a token back to the key of inFlightCalls. It is private static in MCPServer+Call.swift; it must become internal to be used from the elicitation file.
    - swift-sdk Server.requestElicitation(message:requestedSchema:mode:_meta:) and the URL form accept _meta. CallTool.Parameters._meta gives the progressToken to a scripted tool. Thus the test tool can echo the token with no sdk change.
    - Run identity: ToolContext is a struct, not Equatable. Public fields: tool, op, completionToken, sessionID. sessionID, tool and op can be the same for two runs. completionToken is the correlation id of the run, a new ULID for each run. The run that a question links to is holdingRunToken, but that property is internal in Extras e65287a (pins stay). Decision: compare by completionToken (the example of the owner). Limit: each inner tools.* call of one runCode snippet gets its own completionToken (RunBinding.invoke mounts each call), so two inner MCP calls of one snippet do not match in step 2 and need the token echo (step 1).
    - Log: MCPServer.record(_:level:metadata:) writes MultitoolTelemetry.LogMessage. Tests read records with a LogHandler (pattern: StaleConnectDiscardLogHandler in ResilienceTests). MCPTestSupport.connectedMCPServer(to:over:...) has no logger parameter now; I add one with the default MCPServer.defaultLogger.
  timestamp: 2026-10-16T10:00:45.062151+00:00
- actor: claude-code
  id: 01m522ye41zgthteyss0axrad4
  text: 'RED proof (old code, new tests only, one filtered run): 4 tests x 2 transports, all fail as checks, no hang, 0.1 s. a: answer nil (cancel), asking sink 0 questions. b: answer nil, holding sink 0 questions. c: reason check and log record check fail. d: answer nil. Test design: each run has a sink that answers its own question at once on the run plane, so the test only awaits the call; a question that does not reach the run ends as cancel. The two runs share one session and one run plane, so a check by session cannot pass c.'
  timestamp: 2026-10-16T10:08:27.777742+00:00
- actor: claude-code
  id: 01m52360mtspc7pafnc34z4y2g
  text: |-
    ### implement — changed
    - evidence: MCPServer+Elicitation.swift (callingContext(linkedBy:) with token rule then one-run rule; contextOfTheOneRunInFlight(); cancelWithNoAnswerer() with reason and record; resolve passes the _meta of form and URL params), MCPServer+Call.swift (requestID(of:) is internal), MultitoolTelemetry.swift (mcpElicitationNotLinked, mcpElicitationNoAnswerer), MCPElicitationTests.swift (4 new tests x 2 transports), ScriptedServer.swift (addElicitingTool elicitationMeta parameter, progressTokenEcho(of:)), MCPTestSupport.swift (logger parameter), LoopbackTools.swift and ServerMode.swift (doc links).
    - Run identity: completionToken (correlation id; new ULID for each run). Not session id, tool or op. holdingRunToken is internal in Extras e65287a.
    - GREEN: filtered run of the 4 new tests on new code: 8 cases pass. Full run: swift test, 2412 tests in 211 suites passed, exit 0. Only warning in the log: the SwiftPM build note "missing creator for mutated node" for the mlx-swift_Cmlx bundle (not a compiler warning; it is in each build).
    - Limit: two inner tools.* MCP calls of one runCode snippet have different completion tokens, so without a token echo they get the cancel with the reason. A fix needs a public holding run token in FoundationModelsExtras.
    - next: commit, push, CI.
  timestamp: 2026-10-16T10:12:36.122414+00:00
position_column: done
position_ordinal: ffffff8180
title: Attribute a server elicitation to the right call when a server has concurrent calls (elicitation-plan task 26)
---
When one MCP server has two calls in flight, Multitool links a server `elicitation/create` only to the sole call in flight. With two calls, the question gets `cancel`.

Do:
- Start from the new design: one MCP client for each connect attempt.
- Find a way to link the question to the right call. Candidates: the related-request id or `_meta` of the MCP request, if the server sends it; or the progress token.
- If MCP gives no way to know the call, say so, and propose what to do (for example, ask through the session with no tool context).
- Send a short design to the owner before code.
- A fixed-order test with two calls in flight. It fails on the old code as a check.
- One full run. Push when green.

#elicitation-phase-3