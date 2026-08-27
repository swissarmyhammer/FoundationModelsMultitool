---
assignees:
- claude-code
depends_on:
- 01M112CTS4HSY5R312NW7VK7SV
- 01M1142FWBGVZ104BJE5SPHAPZ
- 01M112EG33CSGN466M9BHVD8C0
position_column: todo
position_ordinal: 8a80
title: Route server-initiated elicitation through ToolContext.elicit, with a bare-session handler
---
## What
Make the MCP elicitation passthrough that eventplan.md § "Phases" (phase 4) requires: "The `ElicitationCoordinator` protocol becomes the host seam of `ToolContext.elicit`, URL mode included." The sibling's `ElicitationCoordinator` protocol and `MCPElicitationTool` go away. Router's `ElicitationRequest` / `ElicitationResponse` (in `FoundationModelsRouter/Hosting/Elicitation.swift`) and `SessionMailbox.respond(elicitationId:_:)` / `complete(elicitationId:)` are the one machinery on Router.

**The verb is a plain `Tool`, and elicitation must work on a bare `LanguageModelSession` too.** A question needs an answerer. Three sources, one resolution order:
1. A bound `ToolContext` (Router / MultiTool): `context.elicit(request)`. The run suspends; the turn is not held.
2. Else a host-supplied handler: `MCPServer.init(..., elicitationHandler: (@Sendable (ElicitationRequest) async -> ElicitationResponse)? = nil)`. Apple's tool call holds the turn while the user answers. That is the ordinary cost of a plain tool on a plain session.
3. Else `cancel` to the server. Never a throw into the transport.
Router wins when present, so a Router host never sets the handler. URL-mode completion in case 2: the handler's accept is followed by `MCPServer.complete(elicitationId:)`, a public method the host calls when the URL flow ends; the server relays `notifications/elicitation/complete` to it. In case 1 the same method forwards to the mailbox.

- Source, for the protocol details only: `/Users/wballard/github/swissarmyhammer/FoundationModelsMCP/Sources/FoundationModelsMCP/ElicitationCoordinator.swift` (the "URL-mode elicitation is a three-message flow" documentation and `ElicitationRouting`), and in `MCPServer.swift` the sections `// MARK: - Elicitation completion: notifications/elicitation/complete relay` (lines 3570–3591), `// MARK: - Elicitation` (lines 3673–3818), and `declareElicitationCapabilityAndRegisterHandler(coordinator:)` (line 3709).
- Target: `Sources/FoundationModelsMultitool/Capabilities/MCP/MCPServer+Elicitation.swift`.
- **Registration, with the sdk as pinned (0.12.1).** The capability is already declared: the connection task builds the `Client` with `Elicitation(form: .init(), url: .init())`. This task registers the handler with `Client.withElicitationHandler(_:)` (or `withMethodHandler(CreateElicitation.self, handler:)`) in `setupHandlers()`, always, and registers `ElicitationCompleteNotification` for the relay.
- The handler: decode the MCP request into Router's `ElicitationRequest` (form mode with the restricted flat schema; URL mode with `url`). Find the calling run's captured `ToolContext` in the in-flight table of the call task, with the `ElicitationRouting` rule of the source when more than one call is in flight. Resolve per the order above. Encode the `ElicitationResponse` (`accept` with content, `decline`, `cancel`) as the MCP result.
- `notifications/elicitation/complete` → `MCPServer.complete(elicitationId:)`: the mailbox through the captured context in case 1; the host's pending URL flow in case 2. Unknown and completed ids are ignored, per the spec.
- A form schema outside the restricted subset answers `decline` with a log line. eventplan.md: "Our boundary enforces the restricted form schema for each elicitor."
- Drop `MCPElicitationTool.swift` (the agent-initiated tool). The snippet global `elicit()` and `ToolContext.elicit` already cover that direction.

## Acceptance Criteria
- [ ] Case 1: the loopback `elicitEcho` tool gets the answer the test delivered through `SessionMailbox.respond(elicitationId:_:)`, and the tool result reflects it — over the in-memory transport AND over the in-process HTTP loopback.
- [ ] Case 1, URL mode (`elicitURL`): the accept returns to the server, the call stays open, and it ends only when the test calls `SessionMailbox.complete(elicitationId:)` — over both transports.
- [ ] End to end through `runCode`: a snippet `await tools.<serverName>.elicitEcho({...})` suspends on the server's elicitation, the test answers through `SessionMailbox.respond(elicitationId:_:)`, and the snippet's return value carries the answer — over the HTTP loopback.
- [ ] Case 2: with no `ToolContext` bound and a handler set, `elicitEcho` gets the handler's answer, and `MCPTool.call(arguments:)` returns it in the rendered result. URL mode ends on `MCPServer.complete(elicitationId:)`.
- [ ] Case 3: with no context and no handler, `elicitEcho` gets `cancel`, and the call returns the server's result for a cancelled elicitation, with no throw.
- [ ] With both a context and a handler, the context answers and the handler is never called.
- [ ] `decline` and `cancel` reach the server as those actions. A declined elicitation does not cancel the run.
- [ ] The elicitation event rides the sink as `OperationEventKind.elicitation` with the run's `correlationID` (case 1).
- [ ] `swift build` succeeds, and no `ElicitationCoordinator` symbol exists in this package.

## Tests
- [ ] Port `ElicitationServerTests.swift`, `ElicitationCallContextTests.swift`, and `ElicitationCompleteTests.swift` from `/Users/wballard/github/swissarmyhammer/FoundationModelsMCP/Tests/FoundationModelsMCPTests/` into `Tests/FoundationModelsMultitoolTests/MCPElicitationTests.swift`, with the coordinator stub replaced by a bound `ToolContext` over a real `SessionMailbox`. Parameterize the form and URL cases over `.inMemory` and `.http` with `connectedServer(over:)`. `ScriptedServer.sendElicitationComplete(elicitationId:)` drives the URL-completion cases. Add the `runCode` end-to-end case, the case 2, case 3, and precedence cases. Drop `MCPElicitationToolTests.swift`.
- [ ] Add a gated case in `IntegrationTests/` (imports the `MCPTestServer` product): mount one `MCPTool` for `elicitEcho` on a bare `LanguageModelSession(model: .default, tools:)` with a handler that answers a fixed value, prompt the model to call it, and assert the answer carries that value.
- [ ] `swift test --filter MCPElicitationTests` passes.

## Workflow
- Use `/tdd` — port the tests first, then implement the handler. #eventplan #phase-4