import Foundation
import FoundationModels
import FoundationModelsRouter
import MCP
import MCPTestServer
import Testing
import ULID

@testable import FoundationModelsMultitool

/// Coverage for `MCPServer+Elicitation.swift` — the passthrough of a
/// server-initiated `elicitation/create` to the one elicitation machinery of
/// Router, and the bare-session handler beside it.
///
/// Ported from `ElicitationServerTests.swift`, `ElicitationCallContextTests.swift`
/// and `ElicitationCompleteTests.swift` of
/// `../FoundationModelsMCP/Tests/FoundationModelsMCPTests/`. The sibling
/// routed every request to a stubbed `ElicitationCoordinator`; here the
/// answerer is a bound `ToolContext` over a real `SessionMailbox`, the host's
/// handler, or nothing at all, in that order. The cases of the source that
/// are not here, and why:
///
/// - the detached-call and deadline-suspension cases — a call never detaches,
///   and the engine of Router is the clock of a call made under a context;
/// - the no-secrets-in-form-mode downgrade — the restricted subset is
///   enforced by Router's `ElicitationRequestedSchema`, which the schema case
///   here drives, and the `secret` keyword of the sibling is not a spec field;
/// - the legacy-coordinator cases — no coordinator exists.
///
/// Each case that reaches the server over the wire runs over both transports
/// of ``MCPTransportKind``. The suite is `.serialized` for the reason
/// `LoopbackHTTPServerTests` states: a connect over `.http` holds a live SSE
/// stream and a process-wide registry entry of `LoopbackHTTPServer` open for
/// the whole test, and one test at a time keeps each of them owned by exactly
/// one test.
@Suite("MCPElicitationTests", .serialized)
struct MCPElicitationTests {

    // MARK: - Shared test constants

    /// The name every server of this suite is constructed with, and so the
    /// noun its verbs render under.
    private static let serverName = "loopback"

    /// The two transports every wire case runs over.
    private static let transports: [MCPTransportKind] = [.inMemory, .http]

    /// The answer every accepting case delivers under the answer field.
    private static let scriptedAnswer = "42"

    /// The text the eliciting loopback tools answer for each action.
    private static let acceptText = "elicitation accept"

    /// The text the eliciting loopback tools answer for a decline.
    private static let declineText = "elicitation decline"

    /// The text the eliciting loopback tools answer for a cancel.
    private static let cancelText = "elicitation cancel"

    /// The name of the tool whose `requestedSchema` nests an object.
    private static let nestedToolName = "askNested"

    /// The one field of the nested schema, itself an object.
    private static let nestedFieldName = "profile"

    /// The prompt the nested-schema tool shows.
    private static let nestedMessage = "Fill in your profile."

    /// The JSON Schema type of the nested field — outside the subset.
    private static let objectTypeName = "object"

    /// An elicitation id no flow was ever opened under.
    private static let unknownElicitationId = "never-opened"

    /// The text the echo case sends after a completion, to prove the
    /// connection still answers.
    private static let echoText = "still alive"

    /// How many calls one probe records when the context answers first.
    private static let noHandlerCalls = 0

    /// How many calls one probe records when it is the answerer.
    private static let oneHandlerCall = 1

    /// How many calls stand in flight while an elicitation is held.
    private static let oneCallInFlight = 1

    /// The `runCode` snippet that awaits the eliciting verb with no arguments.
    private static let elicitEchoSnippet =
        "return await tools.\(serverName).\(ScriptedServer.elicitEchoToolName)({});"

    /// The accept every accepting case answers with: ``scriptedAnswer`` under
    /// the answer field the loopback tool requests.
    private static let scriptedAccept = ElicitationResponse.accept(
        content: [ScriptedServer.elicitEchoAnswerField: .string(scriptedAnswer)])

    /// The accept of a URL-mode flow, which carries no content.
    private static let urlAccept = ElicitationResponse.accept(content: nil)

    /// The two answers that are not an accept, beside the text each one
    /// makes the loopback tool answer.
    private static let refusals: [(response: ElicitationResponse, text: String)] = [
        (.decline, declineText),
        (.cancel, cancelText),
    ]

    // MARK: - Helpers

    /// A host handler that records every request it answers and answers each
    /// one with a fixed response.
    private actor HandlerProbe {
        /// Every request the handler answered, in arrival order.
        private(set) var requests: [ElicitationRequest] = []

        /// The response every request is answered with.
        private let response: ElicitationResponse

        /// Creates a probe that answers `response`.
        ///
        /// - Parameter response: The response every request gets.
        init(responding response: ElicitationResponse) {
            self.response = response
        }

        /// Records `request` and answers it.
        ///
        /// - Parameter request: The request the server routed here.
        /// - Returns: The fixed response.
        func answer(_ request: ElicitationRequest) -> ElicitationResponse {
            requests.append(request)
            return response
        }

        /// The handler an `MCPServer` is constructed with.
        nonisolated var handler: MCPServer.ElicitationHandler {
            { request in await self.answer(request) }
        }
    }

    /// The pieces of one run bound around a call: the session the test answers
    /// through, and the context it binds.
    ///
    /// A test cannot own a mailbox or inject a sink — both are internal to
    /// Router — so it owns a stub session instead. The elicitation event is
    /// read off that session's recorded transcript, and the answer is
    /// delivered through `RoutedSession.respond(elicitationId:response:)`.
    private struct BoundRun {
        /// The stub run the elicitation suspends in.
        let stub: StubRun

        /// The context bound around the call.
        var context: ToolContext { stub.context }

        /// The session the answer is delivered through.
        var session: RoutedSession { stub.session }

        /// Builds a fresh run.
        ///
        /// - Throws: whatever standing up the stub session throws.
        init() async throws {
            stub = try await makeStubRun()
        }
    }

    /// A fresh scripted server that serves the three loopback tools, beside a
    /// server named ``serverName`` connected against it over `kind`.
    ///
    /// - Parameters:
    ///   - kind: The transport to connect over.
    ///   - elicitationHandler: The host's answerer, or `nil`.
    /// - Returns: The scripted server, which the test keeps alive, and the
    ///   connected server.
    /// - Throws: What the connect throws.
    private static func connected(
        over kind: MCPTransportKind, elicitationHandler: MCPServer.ElicitationHandler? = nil
    ) async throws -> (scripted: ScriptedServer, server: MCPServer) {
        try await MCPTestSupport.connectedLoopbackMCPServer(
            over: kind, name: serverName, elicitationHandler: elicitationHandler)
    }

    /// Starts one call of `tool` on `server` under `context`, in a task the
    /// test resumes through the mailbox.
    ///
    /// - Parameters:
    ///   - server: The server to call.
    ///   - tool: The name of the tool to call.
    ///   - context: The context to bind around the call.
    /// - Returns: The task of the call.
    private static func startCall(
        _ server: MCPServer, tool: String, under context: ToolContext
    ) -> Task<CallTool.Result, any Error> {
        Task {
            try await ToolContext.$current.withValue(context) {
                try await server.call(name: tool, arguments: nil)
            }
        }
    }

    /// Waits for the elicitation event of the run on `sink`, and returns it.
    ///
    /// - Parameter run: The run to read.
    /// - Returns: The event.
    /// - Throws: When no elicitation event arrives.
    private static func elicitationEvent(on run: BoundRun) async throws -> OperationEvent {
        try await TestPoll.waitUntil("the elicitation event") {
            await !recordedOperationEvents(of: run.stub, ofKind: .elicitation).isEmpty
        }
        return try #require(
            await recordedOperationEvents(of: run.stub, ofKind: .elicitation).first)
    }

    /// The request the elicitation event of `run` carries.
    ///
    /// - Parameter run: The run to read.
    /// - Returns: The request.
    /// - Throws: When no elicitation event arrives, or it carries no request.
    private static func elicitationRequest(on run: BoundRun) async throws -> ElicitationRequest {
        try #require(await elicitationEvent(on: run).elicitation)
    }

    /// The verb of `server` for the tool named `name`.
    ///
    /// - Parameters:
    ///   - name: The name of the discovered tool.
    ///   - server: The connected server.
    /// - Returns: The verb.
    /// - Throws: When `server` discovered no tool named `name`.
    private static func tool(named name: String, on server: MCPServer) async throws -> MCPTool {
        let entry = try #require(await server.tool(named: name))
        return MCPTool(entry: entry, server: server)
    }

    /// The answer field of the `structuredContent` of `result`.
    ///
    /// - Parameter result: The result of an eliciting tool.
    /// - Returns: The answer, or `nil`.
    private static func answer(in result: CallTool.Result) -> String? {
        result.structuredContent?.objectValue?[ScriptedServer.elicitEchoAnswerField]?.stringValue
    }

    /// The rendered text of `result`, as the verb hands it to the model.
    ///
    /// - Parameter result: The result to render.
    /// - Returns: The text.
    private static func rendered(_ result: CallTool.Result) -> String {
        ToolContentRenderer.render(result: result, budget: RenderBudget.default)
    }

    /// The bare call of `tool` with no arguments and no ambient context.
    ///
    /// - Parameter tool: The verb to call.
    /// - Returns: The rendered result.
    /// - Throws: What the verb throws.
    private static func bareCall(_ tool: MCPTool) async throws -> String {
        try await tool.call(arguments: GeneratedContent(properties: [:]))
    }

    // MARK: - Case 1: a bound context answers

    @Test("the answer the test delivers through the mailbox reaches elicitEcho", arguments: transports)
    func theMailboxAnswerReachesTheTool(kind: MCPTransportKind) async throws {
        let (scripted, server) = try await Self.connected(over: kind)
        defer { Task { await server.disconnect() } }
        let run = (try await BoundRun())

        let call = Self.startCall(server, tool: ScriptedServer.elicitEchoToolName, under: run.context)
        let event = try await Self.elicitationEvent(on: run)
        let request = try #require(event.elicitation)
        #expect(request.mode == .form)
        #expect(request.message == ScriptedServer.elicitEchoMessage)
        #expect(request.requestedSchema?.properties.keys.contains(ScriptedServer.elicitEchoAnswerField) == true)
        #expect(event.correlationID == run.context.completionToken)
        await run.session.respond(elicitationId: request.elicitationId.description, response: Self.scriptedAccept)
        let result = try await call.value

        #expect(Self.answer(in: result) == Self.scriptedAnswer)
        #expect(Self.rendered(result).contains(Self.acceptText))
        withExtendedLifetime(scripted) {}
    }

    @Test("a URL-mode accept keeps the call open until the mailbox completes the flow", arguments: transports)
    func aURLAcceptHoldsTheCallUntilTheMailboxCompletes(kind: MCPTransportKind) async throws {
        let (scripted, server) = try await Self.connected(over: kind)
        defer { Task { await server.disconnect() } }
        let run = (try await BoundRun())

        let call = Self.startCall(server, tool: ScriptedServer.elicitURLToolName, under: run.context)
        let request = try await Self.elicitationRequest(on: run)
        #expect(request.mode == .url)
        #expect(request.message == ScriptedServer.elicitURLMessage)
        #expect(request.url?.absoluteString == ScriptedServer.elicitURLLink)
        let delivery = await run.session.respond(elicitationId: request.elicitationId.description, response: Self.urlAccept)
        #expect(delivery == .acceptedAwaitingCompletion)
        #expect(await server.inFlightCalls.count == Self.oneCallInFlight)
        await run.session.complete(elicitationId: request.elicitationId.description)
        let result = try await call.value

        #expect(Self.rendered(result).contains(Self.acceptText))
        withExtendedLifetime(scripted) {}
    }

    @Test("a runCode snippet suspends on the elicitation and returns the mailbox answer over the HTTP loopback")
    func aSnippetSuspendsOnTheElicitationAndReturnsTheAnswer() async throws {
        let (scripted, server) = try await Self.connected(over: .http)
        defer { Task { await server.disconnect() } }
        let registry = try await MultiTool.Builder().withMCP(servers: [server]).buildRegistry()
        let multiTool = MultiTool(registry: registry)
        let run = (try await BoundRun())

        let snippet = Task {
            try await ToolContext.$current.withValue(run.context) {
                try await multiTool.call(arguments: RunCodeArguments(code: Self.elicitEchoSnippet))
            }
        }
        let request = try await Self.elicitationRequest(on: run)
        await run.session.respond(elicitationId: request.elicitationId.description, response: Self.scriptedAccept)
        let output = try await snippet.value

        let returned = try JSONDecoder().decode(String.self, from: Data(output.utf8))
        #expect(returned.contains(Self.scriptedAnswer), "the snippet returned: \(returned)")
        #expect(returned.contains(Self.acceptText))
        withExtendedLifetime(scripted) {}
    }

    // MARK: - Case 2: the host's handler answers a bare call

    @Test("with no context bound, the handler's answer reaches elicitEcho and the rendered result")
    func theHandlerAnswersABareCall() async throws {
        let probe = HandlerProbe(responding: Self.scriptedAccept)
        let (scripted, server) = try await Self.connected(over: .inMemory, elicitationHandler: probe.handler)
        let tool = try await Self.tool(named: ScriptedServer.elicitEchoToolName, on: server)

        let output = try await Self.bareCall(tool)

        #expect(output.contains(Self.scriptedAnswer))
        #expect(output.contains(Self.acceptText))
        let requests = await probe.requests
        #expect(requests.count == Self.oneHandlerCall)
        #expect(requests.first?.mode == .form)
        withExtendedLifetime(scripted) {}
    }

    @Test("with no context bound, a URL-mode accept of the handler ends on MCPServer.complete(elicitationId:)")
    func theHandlerURLAcceptEndsOnComplete() async throws {
        let probe = HandlerProbe(responding: Self.urlAccept)
        let (scripted, server) = try await Self.connected(over: .inMemory, elicitationHandler: probe.handler)
        let tool = try await Self.tool(named: ScriptedServer.elicitURLToolName, on: server)

        let call = Task { try await Self.bareCall(tool) }
        try await TestPoll.waitUntil("the held URL flow") {
            await server.pendingHostElicitationIds == [ScriptedServer.elicitURLElicitationId]
        }
        #expect(await server.inFlightCalls.count == Self.oneCallInFlight)
        await server.complete(elicitationId: ScriptedServer.elicitURLElicitationId)
        let output = try await call.value

        #expect(output.contains(Self.acceptText))
        #expect(await server.pendingHostElicitationIds.isEmpty)
        withExtendedLifetime(scripted) {}
    }

    // MARK: - Case 3: nothing answers

    @Test("with no context and no handler, elicitEcho gets cancel and the call returns without a throw")
    func noContextAndNoHandlerCancels() async throws {
        let (scripted, server) = try await Self.connected(over: .inMemory)
        let tool = try await Self.tool(named: ScriptedServer.elicitEchoToolName, on: server)

        let output = try await Self.bareCall(tool)

        #expect(output.contains(Self.cancelText))
        withExtendedLifetime(scripted) {}
    }

    // MARK: - Precedence

    @Test("with both a context and a handler, the context answers and the handler is never called")
    func theContextWinsOverTheHandler() async throws {
        let probe = HandlerProbe(responding: Self.urlAccept)
        let (scripted, server) = try await Self.connected(over: .inMemory, elicitationHandler: probe.handler)
        let run = (try await BoundRun())

        let call = Self.startCall(server, tool: ScriptedServer.elicitEchoToolName, under: run.context)
        let request = try await Self.elicitationRequest(on: run)
        await run.session.respond(elicitationId: request.elicitationId.description, response: Self.scriptedAccept)
        let result = try await call.value

        #expect(Self.answer(in: result) == Self.scriptedAnswer)
        #expect(await probe.requests.count == Self.noHandlerCalls)
        withExtendedLifetime(scripted) {}
    }

    // MARK: - decline and cancel

    @Test("decline and cancel reach the server as those actions, and neither cancels the run", arguments: refusals)
    func aRefusalReachesTheServerAndKeepsTheRun(refusal: (response: ElicitationResponse, text: String)) async throws {
        let (scripted, server) = try await Self.connected(over: .inMemory)
        let run = (try await BoundRun())

        let call = Self.startCall(server, tool: ScriptedServer.elicitEchoToolName, under: run.context)
        let request = try await Self.elicitationRequest(on: run)
        await run.session.respond(elicitationId: request.elicitationId.description, response: refusal.response)
        let result = try await call.value

        #expect(result.isError != true)
        #expect(Self.rendered(result).contains(refusal.text))
        let echoed = try await ToolContext.$current.withValue(run.context) {
            try await server.call(
                name: ScriptedServer.echoToolName,
                arguments: [ScriptedServer.echoTextArgument: .string(Self.echoText)])
        }
        #expect(Self.rendered(echoed).contains(Self.echoText))
        withExtendedLifetime(scripted) {}
    }

    // MARK: - The restricted form schema

    @Test("a requestedSchema outside the restricted subset is declined before it reaches the run")
    func aSchemaOutsideTheSubsetIsDeclined() async throws {
        let scripted = ScriptedServer()
        await scripted.addElicitingTool(
            named: Self.nestedToolName,
            message: Self.nestedMessage,
            requestedSchema: Elicitation.RequestSchema(
                properties: [Self.nestedFieldName: .object(["type": .string(Self.objectTypeName)])]))
        let server = try await MCPTestSupport.connectedMCPServer(
            to: scripted, over: .inMemory, name: Self.serverName)
        let run = (try await BoundRun())

        let result = try await ToolContext.$current.withValue(run.context) {
            try await server.call(name: Self.nestedToolName, arguments: nil)
        }

        #expect(Self.rendered(result).contains(Self.declineText))
        #expect(await recordedOperationEvents(of: run.stub).isEmpty)
        withExtendedLifetime(scripted) {}
    }

    // MARK: - An unknown completion

    @Test("a completion for an id no flow was opened under is ignored, from the host and from the wire")
    func anUnknownCompletionIsIgnored() async throws {
        let (scripted, server) = try await Self.connected(over: .inMemory)

        await server.complete(elicitationId: Self.unknownElicitationId)
        try await scripted.sendElicitationComplete(elicitationId: Self.unknownElicitationId)
        let echoed = try await server.call(
            name: ScriptedServer.echoToolName,
            arguments: [ScriptedServer.echoTextArgument: .string(Self.echoText)])

        #expect(Self.rendered(echoed).contains(Self.echoText))
        #expect(await server.pendingHostElicitationIds.isEmpty)
        withExtendedLifetime(scripted) {}
    }
}
