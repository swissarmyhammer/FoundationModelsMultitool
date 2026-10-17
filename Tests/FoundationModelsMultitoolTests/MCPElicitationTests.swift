import Foundation
import FoundationModels
import FoundationModelsExtras
import FoundationModelsRouter
import Logging
import MCP
import MCPTestServer
import Synchronization
import Testing
import ULID

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Coverage for `MCPServer+Elicitation.swift` — the passthrough of a
/// server-initiated `elicitation/create` to the one elicitation machinery of
/// Router, and the bare-session handler beside it.
///
/// Ported from `ElicitationServerTests.swift`, `ElicitationCallContextTests.swift`
/// and `ElicitationCompleteTests.swift` of
/// `../FoundationModelsMCP/Tests/FoundationModelsMCPTests/`. The sibling
/// routed every request to a stubbed `ElicitationCoordinator`; here the
/// answerer is a bound `ToolContext` over a real `RunPlane`, the host's
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

    /// How many calls the case of two calls in flight makes.
    private static let twoCalls = 2

    /// The key of the reason in the `_meta` of an elicitation result. The
    /// test spells it out, and does not read the constant of the product, so
    /// the test compiles on the code before the change.
    private static let reasonMetaKey = "reason"

    /// The tool name and the op of the headless context.
    private static let headlessTool = "headless-probe"

    /// The completion token of the headless context.
    private static let headlessCompletionToken = "headless-run"

    /// The tool name and the op of the context of the relay case.
    private static let relayTool = "relay-probe"

    /// The completion token of the context of the relay case.
    private static let relayCompletionToken = "relay-run"

    /// The name of the tool that holds its call until the test releases it:
    /// the first of two calls in flight.
    private static let heldToolName = "holdOpen"

    /// The name of the form-mode eliciting tool that echoes the progress
    /// token of its call in the `_meta` of its `elicitation/create`.
    private static let tokenEchoToolName = "elicitEchoWithToken"

    /// The name of the form-mode eliciting tool that sends a progress token
    /// that names no call in flight.
    private static let unknownTokenToolName = "elicitEchoWithUnknownToken"

    /// The progress token that ``unknownTokenToolName`` sends. No call has
    /// it.
    private static let unknownProgressToken = "no-call-in-flight"

    /// The tool name and the op of each run of the cases of two calls in
    /// flight.
    private static let answeringTool = "answering-probe"

    /// The completion token of the run that holds the first call.
    private static let holdingRunToken = "holding-run"

    /// The completion token of the run that makes the second call.
    private static let askingRunToken = "asking-run"

    /// The answer that the sink of the holding run gives to each question.
    private static let holdingRunAnswer = "answer of the holding run"

    /// The answer that the sink of the asking run gives to each question.
    private static let askingRunAnswer = "answer of the asking run"

    /// How many questions the run that answers gets.
    private static let oneQuestion = 1

    /// The reason of the cancel when the question cannot be linked to one
    /// call. The test spells it out, and does not read the constant of the
    /// product, so the test compiles on the code before the change.
    private static let notLinkedReason =
        "the question cannot be linked to one tool call: 2 calls in flight from different runs"

    /// The message of the record of that cancel, spelled out for the same
    /// reason.
    private static let notLinkedLogMessage =
        "mcp elicitation cancelled: the question cannot be linked to one tool call"

    /// The reason of the cancel that ends a held URL flow when its connection
    /// ends. The test spells it out, and does not read the constant of the
    /// product, so the test compiles on the code before the change.
    private static let connectionEndedReason = "the connection to the MCP server ended before the URL flow completed"

    /// The reason of the decline of a `requestedSchema` outside the
    /// restricted subset. The test spells it out, and does not read the
    /// constant of the product, so the test compiles on the code before the
    /// change.
    private static let schemaOutsideTheSubsetReason =
        "the requested schema is outside the supported subset of the form schema"

    /// The reason of the decline of a URL-mode request whose `url` is not a
    /// valid URL, spelled out for the same reason.
    private static let invalidURLReason = "the url of the URL-mode request is not a valid URL"

    /// The reason of the cancel of a request that arrives after the
    /// `MCPServer` of the client is gone, spelled out for the same reason.
    private static let hostGoneReason = "the host side of the MCP connection no longer exists"

    /// The reason of the cancel of a question that the calling run threw on,
    /// spelled out for the same reason.
    private static let runFailedReason = "the calling run failed to ask the question"

    /// The name of the URL-mode tool whose `url` is not a valid URL.
    private static let invalidURLToolName = "elicitInvalidURL"

    /// The `url` of ``invalidURLToolName``: an empty string, which
    /// `URL(string:)` does not read as a URL.
    private static let invalidURL = ""

    /// A URL-mode `elicitation/create` with the message, the link and the
    /// wire id of the loopback URL tool.
    private static let urlElicitation = CreateElicitation.Parameters.url(
        .init(
            message: ScriptedServer.elicitURLMessage, url: ScriptedServer.elicitURLLink,
            elicitationId: ScriptedServer.elicitURLElicitationId))

    /// The `runCode` snippet that awaits the eliciting verb with no arguments.
    private static let elicitEchoSnippet =
        "return await tools.\(serverName).\(ScriptedServer.elicitEchoToolName)({});"

    /// The name of the tool that answers when a call of the held tool arrived
    /// at the server. A snippet awaits it, thus the held call is in flight
    /// before the snippet starts its next call.
    private static let arrivalWaitToolName = "awaitHeldArrival"

    /// The name of the tool that releases the held tool. A snippet calls it
    /// when it does not need the held call in flight any more.
    private static let releaseToolName = "releaseHeld"

    /// The `runCode` snippet that has two inner calls in flight on one server
    /// at the same time: the held call, and the eliciting call, which sends
    /// no progress token in its `_meta`. The order is fixed: the snippet
    /// starts the held call, waits until it arrived at the server, and only
    /// then starts the eliciting call. After the eliciting call ends, the
    /// snippet releases the held call, awaits it, and returns the result of
    /// the eliciting call.
    private static let heldAndElicitingSnippet = """
        const held = tools.\(serverName).\(heldToolName)({});
        await tools.\(serverName).\(arrivalWaitToolName)({});
        const asked = await tools.\(serverName).\(ScriptedServer.elicitEchoToolName)({});
        await tools.\(serverName).\(releaseToolName)({});
        await held;
        return asked;
        """

    /// The accept every accepting case answers with: ``scriptedAnswer`` under
    /// the answer field the loopback tool requests.
    private static let scriptedAccept = ElicitationResponse.accept(
        content: [ScriptedServer.elicitEchoAnswerField: .string(scriptedAnswer)])

    /// The accept of a URL-mode flow, which carries no content.
    private static let urlAccept = ElicitationResponse.accept(content: nil)

    /// The two answers that are not an accept, beside the text each one
    /// makes the loopback tool answer.
    ///
    /// The tuple names the type with its module: Router declares a typealias
    /// of the same name, and the `@Test` arguments macro cannot resolve the
    /// bare name when this file imports the two modules.
    private static let refusals: [(response: FoundationModelsExtras.ElicitationResponse, text: String)] = [
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
    /// A test cannot own the run plane of a session or inject a sink — both are internal to
    /// Router — so it owns a stub session instead. The elicitation event is
    /// read off that session's recorded transcript, and the answer is
    /// delivered through `RoutedSession.respond(elicitationId:response:)`.
    private struct BoundRun {
        /// The stub run the elicitation suspends in.
        let stub: StubRun

        /// The context bound around the call.
        var context: ToolContext { stub.context }

        /// The session the answer is delivered through.
        var session: any RoutedSession { stub.session }

        /// Builds a fresh run, gives it to `body`, and closes its session
        /// when `body` returns or throws.
        ///
        /// - Parameter body: The work that uses the run.
        /// - Returns: What `body` returned.
        /// - Throws: whatever standing up the stub session throws, or what
        ///   `body` threw.
        static func with<Result>(_ body: (BoundRun) async throws -> Result) async throws -> Result {
            try await withStubRun { stub in try await body(BoundRun(stub: stub)) }
        }
    }

    /// A fresh scripted server that serves the three loopback tools, beside a
    /// server named ``serverName`` connected against it over `kind`.
    ///
    /// - Parameters:
    ///   - kind: The transport to connect over.
    ///   - elicitationHandler: The host's answerer, or `nil`.
    ///   - userPresence: Whether a person is present to answer an
    ///     elicitation. Defaults to `.interactive`, a test-only default: the
    ///     public initializer of `MCPServer` has none.
    /// - Returns: The scripted server, which the test keeps alive, and the
    ///   connected server.
    /// - Throws: What the connect throws.
    private static func connected(
        over kind: MCPTransportKind, elicitationHandler: MCPServer.ElicitationHandler? = nil,
        userPresence: UserPresence = .interactive
    ) async throws -> (scripted: ScriptedServer, server: MCPServer) {
        try await MCPTestSupport.connectedLoopbackMCPServer(
            over: kind, name: serverName, elicitationHandler: elicitationHandler, userPresence: userPresence)
    }

    /// A context over a headless run plane: no person is present, thus the
    /// run plane answers each question with a cancel and
    /// `RunPlane.noUserPresentReason` at once.
    ///
    /// - Returns: The context.
    private static func headlessContext() -> ToolContext {
        ToolContext(
            sessionID: ULID(),
            runPlane: RunPlane(userPresence: .headless),
            sink: RecordingEventSink(),
            tool: headlessTool,
            op: headlessTool,
            completionToken: headlessCompletionToken,
            isCancelled: { false })
    }

    /// A context over `runPlane` that posts to `sink`: a context that the
    /// test owns, thus the test answers and completes its questions on
    /// `runPlane` itself.
    ///
    /// - Parameters:
    ///   - runPlane: The run plane of the context.
    ///   - sink: The sink of the context.
    /// - Returns: The context.
    private static func relayContext(on runPlane: RunPlane, sink: RecordingEventSink) -> ToolContext {
        ToolContext(
            sessionID: ULID(),
            runPlane: runPlane,
            sink: sink,
            tool: relayTool,
            op: relayTool,
            completionToken: relayCompletionToken,
            isCancelled: { false })
    }

    /// The `reason` field of the `_meta` of `result`.
    ///
    /// - Parameter result: The elicitation result the scripted server got.
    /// - Returns: The value, or `nil` when there is no result, no `_meta` or
    ///   no `reason`.
    private static func reason(of result: CreateElicitation.Result?) -> Value? {
        result?._meta?[reasonMetaKey]
    }

    /// Starts one call of `tool` on `server` under `context`, in a task the
    /// test resumes through the run plane.
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
    /// The wait is an event: the recorder of the run resumes it when it
    /// records the elicitation event. It reads no clock and does not poll.
    ///
    /// - Parameter run: The run to read.
    /// - Returns: The event.
    /// - Throws: When no elicitation event arrives before the task is
    ///   cancelled.
    private static func elicitationEvent(on run: BoundRun) async throws -> OperationEvent {
        _ = await run.stub.recorder.waitUntil { events in
            events.contains { $0.kind == .elicitation }
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

    /// The error of a transport factory that makes no transport. A connect
    /// through it fails before it reaches a far end.
    private struct RefusedTransport: Error {}

    /// Starts one URL-mode question on `server`, and waits until `server`
    /// holds the accept of its handler.
    ///
    /// - Parameter server: The server, whose handler accepts the question.
    /// - Returns: The task of the answer that `server` gives.
    /// - Throws: When the answer ended before `server` held the flow.
    private static func startHeldHostFlow(on server: MCPServer) async throws -> Task<CreateElicitation.Result, any Error> {
        try await startHeldHostFlow(on: server) { await server.answerElicitation(parameters: urlElicitation) }
    }

    /// Starts `work`, which makes `server` hold one URL-mode flow, and waits
    /// until `server` holds that flow.
    ///
    /// The wait ends on the first of two events: `server` holds the flow, or
    /// `work` ended with no hold. Each of the two events can occur, thus the
    /// wait always ends. Then this function cancels the wait for the hold and
    /// waits until that wait ended, thus no wait stays open after it returns.
    /// When no flow is held, the test fails at once. When the wait throws, a
    /// held flow ends before the throw, thus `work` does not stay open.
    ///
    /// - Parameters:
    ///   - server: The server, whose handler accepts the question.
    ///   - work: The work that makes `server` hold the flow.
    /// - Returns: The task of `work`.
    /// - Throws: When `work` ended before `server` held the flow, or when
    ///   the task is cancelled first.
    private static func startHeldHostFlow<Success: Sendable>(
        on server: MCPServer, running work: @escaping @Sendable () async throws -> Success
    ) async throws -> Task<Success, any Error> {
        let firstEvent = TestGate()
        let flow = Task {
            defer { firstEvent.open() }
            return try await work()
        }
        let hold = Task {
            await server.waitUntilHostElicitationHeld(elicitationId: ScriptedServer.elicitURLElicitationId)
            firstEvent.open()
        }
        do {
            try await firstEvent.wait()
        } catch {
            await endWait(hold)
            await server.complete(elicitationId: ScriptedServer.elicitURLElicitationId)
            throw error
        }
        await endWait(hold)
        try #require(
            await server.pendingHostElicitationIds == [ScriptedServer.elicitURLElicitationId],
            "the work ended before the server held the URL flow")
        return flow
    }

    /// The two events that end the connection of a URL flow.
    enum ConnectionEnd: CaseIterable, Sendable {
        /// `disconnect()`.
        case disconnect

        /// A new connect, whose factory makes no transport.
        case newConnect
    }

    /// Ends the connection of `server` with `end`.
    ///
    /// - Parameters:
    ///   - server: The connected server.
    ///   - end: The event that ends the connection.
    private static func endConnection(of server: MCPServer, with end: ConnectionEnd) async {
        switch end {
        case .disconnect:
            await server.disconnect()
        case .newConnect:
            await #expect(throws: RefusedTransport.self) {
                try await server.connect(via: { throw RefusedTransport() })
            }
        }
    }

    /// One URL flow that a bound context accepted, and that waits for its
    /// completion.
    private struct ContextURLFlow {
        /// The task of the call that asked the question.
        let call: Task<CallTool.Result, any Error>

        /// The question, with the `ToolContext` id that the server chose.
        let request: ElicitationRequest
    }

    /// Starts one call of the URL tool on `server` under a context over
    /// `runPlane`, waits until the question reaches `sink`, and accepts it.
    /// Then the flow waits for its completion.
    ///
    /// The wait ends on the first of two events: the question reached
    /// `sink`, or the call ended with no question. Each of the two events can
    /// occur, thus the wait always ends. Then this function cancels the wait
    /// for the question and waits until that wait ended, thus no wait stays
    /// open after it returns. When no question came, the test fails at once.
    ///
    /// - Parameters:
    ///   - server: The connected server.
    ///   - runPlane: The run plane of the context.
    ///   - sink: The sink of the context.
    /// - Returns: The flow.
    /// - Throws: When the call ended before the question came, or when the
    ///   task is cancelled first.
    private static func startContextURLFlow(
        on server: MCPServer, runPlane: RunPlane, sink: RecordingEventSink
    ) async throws -> ContextURLFlow {
        let context = relayContext(on: runPlane, sink: sink)
        let firstEvent = TestGate()
        let call = Task {
            defer { firstEvent.open() }
            return try await startCall(server, tool: ScriptedServer.elicitURLToolName, under: context).value
        }
        let asked = Task {
            await sink.waitUntilEvent { $0.kind == .elicitation }
            firstEvent.open()
        }
        do {
            try await firstEvent.wait()
        } catch {
            await endWait(asked)
            throw error
        }
        await endWait(asked)
        let request = try #require(
            await sink.events.first(where: { $0.kind == .elicitation })?.elicitation,
            "the call ended before the question reached the sink")
        let delivery = await runPlane.respond(elicitationId: request.elicitationId, urlAccept)
        try #require(delivery == .acceptedAwaitingCompletion)
        return ContextURLFlow(call: call, request: request)
    }

    /// Cancels `wait`, and waits until it ended. A cancel ends a wait for
    /// the hold of a URL flow, thus this call always returns.
    ///
    /// - Parameter wait: The task of a wait for the hold of a URL flow.
    private static func endWait(_ wait: Task<Void, Never>) async {
        wait.cancel()
        await wait.value
    }

    /// Runs `body`, and then disconnects `server`, also when `body` throws.
    ///
    /// The test awaits the disconnect on each path, thus the connection is
    /// closed before the test ends. A `.http` connection holds a process-wide
    /// registry entry of `LoopbackHTTPServer` until it closes, thus a
    /// connection that stays open after its test is a fixture that leaks into
    /// the next test.
    ///
    /// - Parameters:
    ///   - server: The connected server to disconnect.
    ///   - body: The work of the test on `server`.
    /// - Returns: What `body` returned.
    /// - Throws: What `body` threw, after the disconnect.
    private static func withConnection<Result>(
        of server: MCPServer, _ body: () async throws -> Result
    ) async throws -> Result {
        do {
            let result = try await body()
            await server.disconnect()
            return result
        } catch {
            await server.disconnect()
            throw error
        }
    }

    // MARK: - Case 1: a bound context answers

    @Test("the answer the test delivers through the session reaches elicitEcho", arguments: transports)
    func theSessionAnswerReachesTheTool(kind: MCPTransportKind) async throws {
        let (scripted, server) = try await Self.connected(over: kind)
        try await Self.withConnection(of: server) {
            try await BoundRun.with { run in
                let call = Self.startCall(server, tool: ScriptedServer.elicitEchoToolName, under: run.context)
                let event = try await Self.elicitationEvent(on: run)
                let request = try #require(event.elicitation)
                #expect(request.mode == .form)
                #expect(request.message == ScriptedServer.elicitEchoMessage)
                #expect(
                    request.requestedSchema?.properties.keys.contains(ScriptedServer.elicitEchoAnswerField) == true)
                #expect(event.correlationID == run.context.completionToken)
                await run.session.respond(
                    elicitationId: request.elicitationId.description, response: Self.scriptedAccept)
                let result = try await call.value

                #expect(Self.answer(in: result) == Self.scriptedAnswer)
                #expect(Self.rendered(result).contains(Self.acceptText))
            }
        }
        withExtendedLifetime(scripted) {}
    }

    @Test("a URL-mode accept keeps the call open until the session completes the flow", arguments: transports)
    func aURLAcceptHoldsTheCallUntilTheSessionCompletes(kind: MCPTransportKind) async throws {
        let (scripted, server) = try await Self.connected(over: kind)
        try await Self.withConnection(of: server) {
            try await BoundRun.with { run in
                let call = Self.startCall(server, tool: ScriptedServer.elicitURLToolName, under: run.context)
                let request = try await Self.elicitationRequest(on: run)
                #expect(request.mode == .url)
                #expect(request.message == ScriptedServer.elicitURLMessage)
                #expect(request.url?.absoluteString == ScriptedServer.elicitURLLink)
                let delivery = await run.session.respond(
                    elicitationId: request.elicitationId.description, response: Self.urlAccept)
                #expect(delivery == .acceptedAwaitingCompletion)
                #expect(await server.inFlightCalls.count == Self.oneCallInFlight)
                await run.session.complete(elicitationId: request.elicitationId.description)
                let result = try await call.value

                #expect(Self.rendered(result).contains(Self.acceptText))
            }
        }
        withExtendedLifetime(scripted) {}
    }

    /// The main proof of the relay. The server sends the completion and then
    /// drops the transport. The relay reads the completion before the client
    /// loop, and before the drop, thus the run plane has no open flow when
    /// the call ended. Before the relay, the client loop waited in the
    /// handler, the completion did not reach the run plane, and the flow was
    /// still open after the drop ended the call.
    ///
    /// The drop ends the call in the two cases, thus the test does not wait
    /// for ever. The sink posts the completion in a task of the run plane,
    /// thus the test waits for that post as an event.
    @Test("a wire completion of a URL flow under a context completes the flow on the run plane, one time")
    func aWireCompletionUnderAContextCompletesTheFlow() async throws {
        let (scripted, server) = try await Self.connected(over: .inMemory)
        try await Self.withConnection(of: server) {
            let runPlane = RunPlane(userPresence: .interactive)
            let sink = RecordingEventSink()
            let call = Self.startCall(
                server, tool: ScriptedServer.elicitURLToolName, under: Self.relayContext(on: runPlane, sink: sink))
            await sink.waitUntilEvent { $0.kind == .elicitation }
            let events = await sink.events
            let request = try #require(events.first(where: { $0.kind == .elicitation })?.elicitation)
            let delivery = await runPlane.respond(elicitationId: request.elicitationId, Self.urlAccept)
            #expect(delivery == .acceptedAwaitingCompletion)

            try await scripted.sendElicitationCompleteThenDrop(elicitationId: ScriptedServer.elicitURLElicitationId)
            _ = await call.result
            let lateCompletion = await runPlane.complete(elicitationId: request.elicitationId)
            await sink.waitUntilElicitationCompleted()

            #expect(lateCompletion == .noPendingElicitation)
            #expect(await sink.completedElicitationIds == [request.elicitationId])
        }
        withExtendedLifetime(scripted) {}
    }

    @Test("a runCode snippet suspends on the elicitation and returns the session answer over the HTTP loopback")
    func aSnippetSuspendsOnTheElicitationAndReturnsTheAnswer() async throws {
        let (scripted, server) = try await Self.connected(over: .http)
        try await Self.withConnection(of: server) {
            let registry = try await MultiTool.Builder().withMCP(servers: [server]).buildRegistry()
            let multiTool = MultiTool(registry: registry)
            try await BoundRun.with { run in
                let snippet = Task {
                    try await ToolContext.$current.withValue(run.context) {
                        try await multiTool.call(arguments: RunCodeArguments(code: Self.elicitEchoSnippet))
                    }
                }
                let request = try await Self.elicitationRequest(on: run)
                await run.session.respond(
                    elicitationId: request.elicitationId.description, response: Self.scriptedAccept)
                let output = try await snippet.value

                let returned = try JSONDecoder().decode(String.self, from: Data(output.utf8))
                #expect(returned.contains(Self.scriptedAnswer), "the snippet returned: \(returned)")
                #expect(returned.contains(Self.acceptText))
            }
        }
        withExtendedLifetime(scripted) {}
    }

    /// The host shows the `source` of a question as the one that asks. For a
    /// question of an MCP server, that is the server, and not the `runCode`
    /// tool whose snippet made the call. The sink answers each question of
    /// the run, thus the snippet returns, and then the test reads the request
    /// that the sink observed.
    @Test("a question of an MCP server reaches the sink with the name of the server as its source")
    func aServerQuestionHasTheServerNameAsItsSource() async throws {
        let (scripted, server) = try await Self.connected(over: .inMemory)
        try await Self.withConnection(of: server) {
            let registry = try await MultiTool.Builder().withMCP(servers: [server]).buildRegistry()
            try await withStubRun { stub in
                try await withScriptedElicitationSink(run: stub, answering: Self.scriptedAccept) { sink in
                    _ = try await runSnippet(Self.elicitEchoSnippet, over: registry, under: stub.context)
                    let request = try #require(await sink.observedRequest)

                    #expect(request.source == Self.serverName)
                }
            }
        }
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

        let call = try await Self.startHeldHostFlow(on: server) { try await Self.bareCall(tool) }
        #expect(await server.inFlightCalls.count == Self.oneCallInFlight)
        await server.complete(elicitationId: ScriptedServer.elicitURLElicitationId)
        let output = try await call.value

        #expect(output.contains(Self.acceptText))
        #expect(await server.pendingHostElicitationIds.isEmpty)
        withExtendedLifetime(scripted) {}
    }

    /// The held accept of the handler ends on a wire completion. The server
    /// sends the completion and then drops the transport. The relay ends the
    /// held flow before the drop reaches the client, thus no flow is held
    /// when the drop ended the call. Before the relay, the handler held the
    /// client loop, the completion did not reach
    /// ``MCPServer/complete(elicitationId:)``, and the flow was still held
    /// after the drop ended the call.
    @Test("with no context bound, a wire completion ends the held URL accept of the handler before the drop")
    func aWireCompletionEndsTheHeldHandlerAccept() async throws {
        let probe = HandlerProbe(responding: Self.urlAccept)
        let (scripted, server) = try await Self.connected(over: .inMemory, elicitationHandler: probe.handler)
        let tool = try await Self.tool(named: ScriptedServer.elicitURLToolName, on: server)

        let call = try await Self.startHeldHostFlow(on: server) { try await Self.bareCall(tool) }
        try await scripted.sendElicitationCompleteThenDrop(elicitationId: ScriptedServer.elicitURLElicitationId)
        _ = await call.result
        let heldAfterTheCall = await server.pendingHostElicitationIds
        // A flow that is still held ends here, thus no continuation stays.
        await server.complete(elicitationId: ScriptedServer.elicitURLElicitationId)

        #expect(heldAfterTheCall.isEmpty)
        withExtendedLifetime(scripted) {}
    }

    /// A held accept of the handler waits for a completion that only its
    /// connection can carry. A disconnect ends that connection, thus it ends
    /// the flow with a cancel and a reason, and the handler returns. Before
    /// the fix, the flow stayed held after the disconnect, and the teardown
    /// of the client then waited for ever on the handler.
    ///
    /// The order is fixed: the server holds the flow, the test disconnects,
    /// and then the test reads the held flows before it waits for the answer.
    /// Thus a flow that stays held fails the test, and no wait stays open.
    @Test("with no context bound, a disconnect ends the held URL accept of the handler with cancel and a reason")
    func aDisconnectEndsTheHeldHandlerAccept() async throws {
        let probe = HandlerProbe(responding: Self.urlAccept)
        let server = MCPTestSupport.makeServer(name: Self.serverName, elicitationHandler: probe.handler)
        let answer = try await Self.startHeldHostFlow(on: server)

        await server.disconnect()

        let heldAfterTheDisconnect = await server.pendingHostElicitationIds
        // A flow that is still held ends here, thus no continuation stays.
        await server.complete(elicitationId: ScriptedServer.elicitURLElicitationId)
        try #require(heldAfterTheDisconnect.isEmpty, "the disconnect left the URL flow held")
        let result = try await answer.value
        #expect(result.action == .cancel)
        #expect(Self.reason(of: result) == .string(Self.connectionEndedReason))
    }

    /// A new connect replaces the connection of a held accept, thus it ends
    /// the flow with a cancel and a reason, as a disconnect does. The new
    /// connect then fails, because its factory makes no transport: the old
    /// connection ended when the new connect started.
    ///
    /// The order is fixed, for the reason the disconnect case states.
    @Test("with no context bound, a new connect ends the held URL accept of the handler with cancel and a reason")
    func aNewConnectEndsTheHeldHandlerAccept() async throws {
        let probe = HandlerProbe(responding: Self.urlAccept)
        let server = MCPTestSupport.makeServer(name: Self.serverName, elicitationHandler: probe.handler)
        let answer = try await Self.startHeldHostFlow(on: server)

        await #expect(throws: RefusedTransport.self) {
            try await server.connect(via: { throw RefusedTransport() })
        }

        let heldAfterTheConnect = await server.pendingHostElicitationIds
        // A flow that is still held ends here, thus no continuation stays.
        await server.complete(elicitationId: ScriptedServer.elicitURLElicitationId)
        try #require(heldAfterTheConnect.isEmpty, "the new connect left the URL flow held")
        let result = try await answer.value
        #expect(result.action == .cancel)
        #expect(Self.reason(of: result) == .string(Self.connectionEndedReason))
    }

    /// An accepted URL flow of a bound context waits for a completion that
    /// only its connection can carry: a completion that an old connection
    /// relays is dropped. A disconnect and a new connect end that
    /// connection, thus each ends the open question of the flow with a
    /// cancel and a reason. Before the fix, the question stayed open after
    /// the end of its connection, and nothing could end it.
    ///
    /// The order is fixed: the context accepts the flow, the connection
    /// ends, and then the test reads the ended questions and the open
    /// entries before it waits for the call. Then the test completes a
    /// question that is still open, and a disconnect ends the call that a
    /// new connect left in flight. Thus a question that stays open fails the
    /// test, and no wait stays open.
    @Test(
        "the end of a connection ends the open URL flow of a context with cancel and a reason",
        arguments: ConnectionEnd.allCases)
    func theEndOfAConnectionEndsTheContextURLFlow(end: ConnectionEnd) async throws {
        let (scripted, server) = try await Self.connected(over: .inMemory)
        try await Self.withConnection(of: server) {
            let runPlane = RunPlane(userPresence: .interactive)
            let sink = RecordingEventSink()
            let flow = try await Self.startContextURLFlow(on: server, runPlane: runPlane, sink: sink)

            await Self.endConnection(of: server, with: end)

            let endedAfterTheEnd = await sink.endedElicitations
            let entriesAfterTheEnd = await server.pendingContextElicitations.count
            // A question that is still open ends here, thus no wait stays.
            let lateCompletion = await runPlane.complete(elicitationId: flow.request.elicitationId)
            await server.disconnect()
            _ = await flow.call.result
            #expect(
                endedAfterTheEnd == [
                    RecordingEventSink.EndedElicitation(
                        elicitationId: flow.request.elicitationId,
                        response: .cancel(reason: Self.connectionEndedReason))
                ])
            #expect(entriesAfterTheEnd == 0)
            #expect(lateCompletion == .noPendingElicitation)
        }
        withExtendedLifetime(scripted) {}
    }

    /// A cancel ends a wait for the hold of a URL flow. Thus a helper that
    /// cancels its wait when the flow ended with no hold leaves no
    /// continuation open.
    ///
    /// The order is fixed. The wait starts on a task that is cancelled
    /// already, thus the cancel comes before the hold. Then the server
    /// holds a flow of the same id, so the wait also ends when the cancel
    /// does not end it. The test reads which event ended the wait, and then
    /// ends the flow.
    @Test("a cancel ends a wait for the hold of a URL flow before the server holds the flow")
    func aCancelEndsTheWaitForTheHold() async throws {
        let probe = HandlerProbe(responding: Self.urlAccept)
        let server = MCPTestSupport.makeServer(name: Self.serverName, elicitationHandler: probe.handler)

        let endedOnTheHold = try await withThrowingTaskGroup(of: Bool.self) { group in
            group.cancelAll()
            group.addTask {
                await server.waitUntilHostElicitationHeld(elicitationId: ScriptedServer.elicitURLElicitationId)
            }
            let answer = try await Self.startHeldHostFlow(on: server)
            let ended = try await group.next()
            await server.complete(elicitationId: ScriptedServer.elicitURLElicitationId)
            _ = try await answer.value
            return ended
        }

        #expect(endedOnTheHold == false)
        #expect(await server.hostElicitationHeldWaiters.isEmpty)
    }

    /// A cancel that comes during a wait for the hold of a URL flow ends the
    /// wait with `false`, and leaves no waiter.
    ///
    /// The order is fixed. The wait starts on a live task, and the server
    /// holds no flow. The test waits for the first of two events: the server
    /// recorded the wait, or the wait ended. Each event can occur, thus that
    /// wait always ends. Then the test cancels the wait and reads its result.
    /// When the gate wait throws, the test ends each task before the throw.
    @Test("a cancel during a wait for the hold of a URL flow ends the wait with false")
    func aCancelDuringTheWaitEndsIt() async throws {
        let server = MCPTestSupport.makeServer(name: Self.serverName)
        let wait = Task {
            await server.waitUntilHostElicitationHeld(elicitationId: ScriptedServer.elicitURLElicitationId)
        }
        let firstEvent = TestGate()
        let recorded = Task {
            await server.waitUntilHostElicitationHeldWaitIsRecorded(
                elicitationId: ScriptedServer.elicitURLElicitationId)
            firstEvent.open()
        }
        let ended = Task {
            _ = await wait.value
            firstEvent.open()
        }
        do {
            try await firstEvent.wait()
        } catch {
            await Self.endWait(recorded)
            wait.cancel()
            await ended.value
            throw error
        }
        await Self.endWait(recorded)
        let waitersBeforeTheCancel = await server.hostElicitationHeldWaiters.count

        wait.cancel()
        let endedOnTheHold = await wait.value
        await ended.value

        #expect(waitersBeforeTheCancel == 1)
        #expect(endedOnTheHold == false)
        #expect(await server.hostElicitationHeldWaiters.isEmpty)
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
        try await BoundRun.with { run in
            let call = Self.startCall(server, tool: ScriptedServer.elicitEchoToolName, under: run.context)
            let request = try await Self.elicitationRequest(on: run)
            await run.session.respond(elicitationId: request.elicitationId.description, response: Self.scriptedAccept)
            let result = try await call.value

            #expect(Self.answer(in: result) == Self.scriptedAnswer)
            #expect(await probe.requests.count == Self.noHandlerCalls)
        }
        withExtendedLifetime(scripted) {}
    }

    // MARK: - Two calls in flight: helpers

    /// A sink that answers each question of its run at once, on the run
    /// plane of the run, and records each question it got.
    ///
    /// The answer comes from the sink, thus a question that reaches the run
    /// ends with no step of the test. A question that does not reach the run
    /// ends some other way, for example with a cancel. Thus the test only
    /// awaits the call, and no wait of the test can stay open.
    private actor AnsweringEventSink: OperationEventSink {
        /// The run plane the sink answers on.
        private let runPlane: RunPlane

        /// The answer each question gets.
        private let response: ElicitationResponse

        /// Each question this sink got, in arrival order.
        private(set) var questions: [ElicitationRequest] = []

        /// Makes a sink that answers each question on `runPlane` with
        /// `response`.
        ///
        /// - Parameters:
        ///   - runPlane: The run plane of the run of the sink.
        ///   - response: The answer each question gets.
        init(answeringOn runPlane: RunPlane, with response: ElicitationResponse) {
            self.runPlane = runPlane
            self.response = response
        }

        /// Records the question that `event` carries, and answers it. An
        /// event that carries no question is ignored.
        ///
        /// - Parameter event: The posted event.
        func post(event: OperationEvent) async {
            guard let question = event.elicitation else { return }
            questions.append(question)
            _ = await runPlane.respond(elicitationId: question.elicitationId, response)
        }
    }

    /// One run of a case of two calls in flight: the context the test binds
    /// around a call, and the sink that answers the questions of the run.
    private struct AnsweringRun {
        /// The context of the run.
        let context: ToolContext

        /// The sink of the run.
        let sink: AnsweringEventSink

        /// Makes a run of the session `sessionID` on `runPlane`, with the
        /// completion token `completionToken`. Its sink accepts each question
        /// with `answer` under the answer field of the loopback tools.
        ///
        /// - Parameters:
        ///   - sessionID: The session of the run.
        ///   - runPlane: The run plane of the session.
        ///   - completionToken: The completion token of the run.
        ///   - answer: The answer the sink gives.
        init(session sessionID: ULID, runPlane: RunPlane, completionToken: String, answer: String) {
            sink = AnsweringEventSink(
                answeringOn: runPlane,
                with: .accept(content: [ScriptedServer.elicitEchoAnswerField: .string(answer)]))
            context = ToolContext(
                sessionID: sessionID, runPlane: runPlane, sink: sink, tool: answeringTool, op: answeringTool,
                completionToken: completionToken, isCancelled: { false })
        }
    }

    /// The two runs of a case of two calls in flight: one session and one run
    /// plane, two completion tokens, and two answers. The two runs share the
    /// session, thus a check that tells them apart cannot use the session.
    ///
    /// - Returns: The run that holds the first call, and the run that asks.
    private static func twoRunsOfOneSession() -> (holding: AnsweringRun, asking: AnsweringRun) {
        let sessionID = ULID()
        let runPlane = RunPlane(userPresence: .interactive)
        return (
            AnsweringRun(
                session: sessionID, runPlane: runPlane, completionToken: holdingRunToken, answer: holdingRunAnswer),
            AnsweringRun(
                session: sessionID, runPlane: runPlane, completionToken: askingRunToken, answer: askingRunAnswer)
        )
    }

    /// The log messages that a ``RecordingLogHandler`` got, in order.
    private final class RecordedLogMessages: Sendable {
        /// The messages.
        private let storage = Mutex<[String]>([])

        /// Each message, in order.
        var messages: [String] {
            storage.withLock { $0 }
        }

        /// Adds `message`.
        ///
        /// - Parameter message: The message of one record.
        func append(_ message: String) {
            storage.withLock { $0.append(message) }
        }

        /// A logger that records each message here.
        var logger: Logger {
            Logger(label: "mcp-elicitation-test.recorded") { _ in RecordingLogHandler(recorded: self) }
        }
    }

    /// A `LogHandler` that records the message of each record, at each level.
    private struct RecordingLogHandler: LogHandler {
        /// Where the messages go.
        let recorded: RecordedLogMessages

        /// The metadata of the handler. The handler does not read it.
        var metadata: Logger.Metadata = [:]

        /// The lowest level the handler gets: each level.
        var logLevel: Logger.Level = .trace

        /// Reads or writes one value of ``metadata``.
        ///
        /// - Parameter key: The key of the value.
        subscript(metadataKey key: String) -> Logger.Metadata.Value? {
            get { metadata[key] }
            set { metadata[key] = newValue }
        }

        /// Records the message of `event`.
        ///
        /// - Parameter event: The record.
        func log(event: LogEvent) {
            recorded.append(event.message.description)
        }
    }

    /// A scripted tool with no arguments that does `step`, and then answers
    /// its own name as text.
    ///
    /// - Parameters:
    ///   - name: The name of the tool.
    ///   - description: The description of the tool.
    ///   - step: The work of each call.
    /// - Returns: The tool.
    private static func steppingTool(
        named name: String, description: String, step: @escaping @Sendable () async throws -> Void
    ) -> ScriptedTool {
        ScriptedTool(
            definition: MCP.Tool(name: name, description: description, inputSchema: JSONSchemaBuilder.emptySchema)
        ) { _ in
            try await step()
            return CallTool.Result(content: [.text(text: name, annotations: nil, _meta: nil)])
        }
    }

    /// The two tools that let a snippet set the order of its calls around
    /// `held`: one waits until a call of `held` arrived at the server, and
    /// one releases `held`. Thus a snippet orders its calls by events, and
    /// not by time.
    ///
    /// - Parameter held: The held tool.
    /// - Returns: The tool named ``arrivalWaitToolName`` and the tool named
    ///   ``releaseToolName``.
    private static func orderingTools(for held: HeldScriptedTool) -> [ScriptedTool] {
        [
            steppingTool(
                named: arrivalWaitToolName, description: "Answers when a call of the held tool arrived."
            ) { try await held.waitForArrival() },
            steppingTool(named: releaseToolName, description: "Releases the held tool.") { await held.release() },
        ]
    }

    /// A fresh scripted server that serves the held tool, the two tools that
    /// order calls around it, the loopback tools, the tool that echoes its
    /// progress token, and the tool that sends a token of no call, beside a
    /// server named ``serverName`` connected against it over `kind`.
    ///
    /// - Parameters:
    ///   - kind: The transport to connect over.
    ///   - logger: The logger of the connected server.
    /// - Returns: The scripted server, which the test keeps alive, the
    ///   connected server, and the held tool.
    /// - Throws: What the connect throws.
    private static func connectedForTwoCalls(
        over kind: MCPTransportKind, logger: Logger = MCPServer.defaultLogger
    ) async throws -> (scripted: ScriptedServer, server: MCPServer, held: HeldScriptedTool) {
        let scripted = ScriptedServer()
        let held = HeldScriptedTool(named: heldToolName)
        await scripted.addTool(held.scriptedTool)
        for tool in orderingTools(for: held) {
            await scripted.addTool(tool)
        }
        await scripted.addLoopbackTools()
        await scripted.addElicitingTool(
            named: tokenEchoToolName, message: ScriptedServer.elicitEchoMessage,
            requestedSchema: ScriptedServer.elicitEchoRequestedSchema,
            elicitationMeta: { ScriptedServer.progressTokenEcho(of: $0) })
        await scripted.addElicitingTool(
            named: unknownTokenToolName, message: ScriptedServer.elicitEchoMessage,
            requestedSchema: ScriptedServer.elicitEchoRequestedSchema,
            elicitationMeta: { _ in Metadata(progressToken: .string(unknownProgressToken)) })
        let server = try await MCPTestSupport.connectedMCPServer(
            to: scripted, over: kind, name: serverName, logger: logger)
        return (scripted, server, held)
    }

    /// Calls `tool` on `server` under `asking`, while a call of `held` under
    /// `holding` is in flight, and returns the result of `tool`.
    ///
    /// The order is fixed: the held call starts, and the test waits until it
    /// arrived at the server. Thus the held call is in flight before the
    /// second call starts. When the second call ends, the test releases the
    /// held call and awaits it, also when the second call throws.
    ///
    /// - Parameters:
    ///   - tool: The name of the tool of the second call.
    ///   - asking: The context of the second call.
    ///   - held: The held tool of the first call.
    ///   - holding: The context of the first call.
    ///   - server: The connected server.
    /// - Returns: The result of the second call.
    /// - Throws: What the second call throws, or what the held call throws.
    private static func call(
        _ tool: String, under asking: ToolContext,
        whileHolding held: HeldScriptedTool, under holding: ToolContext, on server: MCPServer
    ) async throws -> CallTool.Result {
        let holdingCall = startCall(server, tool: held.name, under: holding)
        try await held.waitForArrival()
        let asked = await startCall(server, tool: tool, under: asking).result
        await held.release()
        _ = try await holdingCall.value
        return try asked.get()
    }

    // MARK: - Two calls in flight

    @Test(
        "a question that echoes the progress token of its call reaches the run of that call, not the other run",
        arguments: transports)
    func theProgressTokenLinksTheQuestionToItsCall(kind: MCPTransportKind) async throws {
        let (scripted, server, held) = try await Self.connectedForTwoCalls(over: kind)
        try await Self.withConnection(of: server) {
            let (holding, asking) = Self.twoRunsOfOneSession()

            let result = try await Self.call(
                Self.tokenEchoToolName, under: asking.context, whileHolding: held, under: holding.context, on: server)

            #expect(Self.answer(in: result) == Self.askingRunAnswer, "the call returned: \(Self.rendered(result))")
            #expect(await asking.sink.questions.count == Self.oneQuestion)
            #expect(await holding.sink.questions.isEmpty)
        }
        withExtendedLifetime(scripted) {}
    }

    @Test(
        "with two calls in flight from one run and no progress token, the question reaches that run",
        arguments: transports)
    func oneRunInFlightGetsTheQuestion(kind: MCPTransportKind) async throws {
        let (scripted, server, held) = try await Self.connectedForTwoCalls(over: kind)
        try await Self.withConnection(of: server) {
            let (holding, _) = Self.twoRunsOfOneSession()

            let result = try await Self.call(
                ScriptedServer.elicitEchoToolName, under: holding.context, whileHolding: held, under: holding.context,
                on: server)

            #expect(Self.answer(in: result) == Self.holdingRunAnswer, "the call returned: \(Self.rendered(result))")
            #expect(await holding.sink.questions.count == Self.oneQuestion)
        }
        withExtendedLifetime(scripted) {}
    }

    @Test(
        "with two calls in flight from two runs, no progress token and no handler, the question gets cancel with the reason",
        arguments: transports)
    func twoRunsWithNoLinkCancelWithTheReason(kind: MCPTransportKind) async throws {
        let recorded = RecordedLogMessages()
        let (scripted, server, held) = try await Self.connectedForTwoCalls(over: kind, logger: recorded.logger)
        try await Self.withConnection(of: server) {
            let (holding, asking) = Self.twoRunsOfOneSession()

            let result = try await Self.call(
                ScriptedServer.elicitEchoToolName, under: asking.context, whileHolding: held, under: holding.context,
                on: server)

            #expect(Self.rendered(result).contains(Self.cancelText))
            let received = await scripted.receivedElicitationResults.last
            #expect(received?.action == .cancel)
            #expect(Self.reason(of: received) == .string(Self.notLinkedReason))
            #expect(recorded.messages.contains(Self.notLinkedLogMessage))
            #expect(await holding.sink.questions.isEmpty)
            #expect(await asking.sink.questions.isEmpty)
        }
        withExtendedLifetime(scripted) {}
    }

    @Test(
        "a progress token that names no call in flight falls to the one run in flight",
        arguments: transports)
    func anUnknownProgressTokenFallsToTheOneRun(kind: MCPTransportKind) async throws {
        let (scripted, server, held) = try await Self.connectedForTwoCalls(over: kind)
        try await Self.withConnection(of: server) {
            let (holding, _) = Self.twoRunsOfOneSession()

            let result = try await Self.call(
                Self.unknownTokenToolName, under: holding.context, whileHolding: held, under: holding.context,
                on: server)

            #expect(Self.answer(in: result) == Self.holdingRunAnswer, "the call returned: \(Self.rendered(result))")
            #expect(await holding.sink.questions.count == Self.oneQuestion)
        }
        withExtendedLifetime(scripted) {}
    }

    /// Each inner `tools.*` call of a snippet is a run with its own
    /// completion token, and the `runCode` run holds each of them. Thus a
    /// question of one of two inner calls in flight, with no progress token,
    /// links to the `runCode` run. A comparison by the completion token of
    /// each call sees two runs, and cancels the question.
    @Test(
        "with two inner calls of one runCode snippet in flight and no progress token, the question reaches the runCode run",
        arguments: transports)
    func twoInnerCallsOfOneSnippetLinkTheQuestionToTheSnippetRun(kind: MCPTransportKind) async throws {
        let (scripted, server, held) = try await Self.connectedForTwoCalls(over: kind)
        try await Self.withConnection(of: server) {
            let registry = try await MultiTool.Builder().withMCP(servers: [server]).buildRegistry()
            let multiTool = MultiTool(registry: registry)
            let (snippetRun, _) = Self.twoRunsOfOneSession()

            let snippet = Task {
                try await ToolContext.$current.withValue(snippetRun.context) {
                    try await multiTool.call(arguments: RunCodeArguments(code: Self.heldAndElicitingSnippet))
                }
            }
            let output = await snippet.result
            // A snippet that failed before its own release leaves the held call
            // open. The release ends it, and a second release changes nothing.
            await held.release()

            let returned = try JSONDecoder().decode(String.self, from: Data(output.get().utf8))
            #expect(returned.contains(Self.holdingRunAnswer), "the snippet returned: \(returned)")
            #expect(returned.contains(Self.acceptText), "the snippet returned: \(returned)")
            #expect(await snippetRun.sink.questions.count == Self.oneQuestion)
        }
        withExtendedLifetime(scripted) {}
    }

    // MARK: - decline and cancel

    @Test("decline and cancel reach the server as those actions, and neither cancels the run", arguments: refusals)
    func aRefusalReachesTheServerAndKeepsTheRun(
        refusal: (response: FoundationModelsExtras.ElicitationResponse, text: String)
    ) async throws {
        let (scripted, server) = try await Self.connected(over: .inMemory)
        try await BoundRun.with { run in
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
        }
        withExtendedLifetime(scripted) {}
    }

    // MARK: - A headless session

    @Test("under a headless context, elicitEcho gets cancel with the no-user-present reason in _meta")
    func aHeadlessContextCancelsWithTheReason() async throws {
        let (scripted, server) = try await Self.connected(over: .inMemory)

        let result = try await ToolContext.$current.withValue(Self.headlessContext()) {
            try await server.call(name: ScriptedServer.elicitEchoToolName, arguments: nil)
        }

        #expect(Self.rendered(result).contains(Self.cancelText))
        let received = await scripted.receivedElicitationResults.last
        #expect(received?.action == .cancel)
        #expect(Self.reason(of: received) == .string(RunPlane.noUserPresentReason))
        withExtendedLifetime(scripted) {}
    }

    @Test("a headless server cancels a bare elicitEcho with the reason, and never calls the handler")
    func aHeadlessServerCancelsWithoutTheHandler() async throws {
        let probe = HandlerProbe(responding: Self.scriptedAccept)
        let (scripted, server) = try await Self.connected(
            over: .inMemory, elicitationHandler: probe.handler, userPresence: .headless)
        let tool = try await Self.tool(named: ScriptedServer.elicitEchoToolName, on: server)

        let output = try await Self.bareCall(tool)

        #expect(output.contains(Self.cancelText))
        let received = await scripted.receivedElicitationResults.last
        #expect(received?.action == .cancel)
        #expect(Self.reason(of: received) == .string(RunPlane.noUserPresentReason))
        #expect(await probe.requests.count == Self.noHandlerCalls)
        withExtendedLifetime(scripted) {}
    }

    @Test("two elicitEcho calls in flight on a headless server each get cancel with the reason")
    func twoCallsOnAHeadlessServerEachCancelWithTheReason() async throws {
        let probe = HandlerProbe(responding: Self.scriptedAccept)
        let (scripted, server) = try await Self.connected(
            over: .inMemory, elicitationHandler: probe.handler, userPresence: .headless)
        let tool = try await Self.tool(named: ScriptedServer.elicitEchoToolName, on: server)

        async let first = Self.bareCall(tool)
        async let second = Self.bareCall(tool)
        let outputs = try await [first, second]

        #expect(outputs.allSatisfy { $0.contains(Self.cancelText) })
        let received = await scripted.receivedElicitationResults
        #expect(received.count == Self.twoCalls)
        #expect(received.allSatisfy { $0.action == .cancel })
        #expect(received.allSatisfy { Self.reason(of: $0) == .string(RunPlane.noUserPresentReason) })
        #expect(await probe.requests.count == Self.noHandlerCalls)
        withExtendedLifetime(scripted) {}
    }

    // MARK: - The restricted form schema

    /// A fresh scripted server that serves ``nestedToolName``, whose
    /// `requestedSchema` nests an object, beside a server named
    /// ``serverName`` connected against it in memory.
    ///
    /// - Returns: The scripted server, which the test keeps alive, and the
    ///   connected server.
    /// - Throws: What the connect throws.
    private static func connectedForTheNestedSchema() async throws -> (scripted: ScriptedServer, server: MCPServer) {
        let scripted = ScriptedServer()
        await scripted.addElicitingTool(
            named: nestedToolName,
            message: nestedMessage,
            requestedSchema: Elicitation.RequestSchema(
                properties: [nestedFieldName: .object(["type": .string(objectTypeName)])]))
        let server = try await MCPTestSupport.connectedMCPServer(to: scripted, over: .inMemory, name: serverName)
        return (scripted, server)
    }

    @Test("a requestedSchema outside the restricted subset is declined before it reaches the run")
    func aSchemaOutsideTheSubsetIsDeclined() async throws {
        let (scripted, server) = try await Self.connectedForTheNestedSchema()
        try await BoundRun.with { run in
            let result = try await ToolContext.$current.withValue(run.context) {
                try await server.call(name: Self.nestedToolName, arguments: nil)
            }

            #expect(Self.rendered(result).contains(Self.declineText))
            #expect(await recordedOperationEvents(of: run.stub).isEmpty)
        }
        withExtendedLifetime(scripted) {}
    }

    // MARK: - Each decline and cancel of Multitool gives a reason

    /// The error of a calling run that fails to ask its question.
    private struct FailedRun: Error {}

    /// A decline that Multitool makes for a schema outside the subset tells
    /// the server why, under the `reason` key of `_meta`. Before the fix, the
    /// decline had no `_meta`, and only the log held the cause.
    @Test("a requestedSchema outside the restricted subset reaches the server as decline with the reason")
    func aSchemaOutsideTheSubsetDeclinesWithTheReason() async throws {
        let (scripted, server) = try await Self.connectedForTheNestedSchema()
        try await Self.withConnection(of: server) {
            _ = try await server.call(name: Self.nestedToolName, arguments: nil)

            let received = await scripted.receivedElicitationResults.last
            #expect(received?.action == .decline)
            #expect(Self.reason(of: received) == .string(Self.schemaOutsideTheSubsetReason))
        }
        withExtendedLifetime(scripted) {}
    }

    /// A decline that Multitool makes for a `url` that is not a valid URL
    /// tells the server why. Before the fix, the decline had no `_meta`.
    @Test("a URL-mode request whose url is not valid reaches the server as decline with the reason")
    func anInvalidURLDeclinesWithTheReason() async throws {
        let scripted = ScriptedServer()
        await scripted.addURLElicitingTool(
            named: Self.invalidURLToolName, message: ScriptedServer.elicitURLMessage, url: Self.invalidURL,
            elicitationId: ScriptedServer.elicitURLElicitationId)
        let server = try await MCPTestSupport.connectedMCPServer(to: scripted, over: .inMemory, name: Self.serverName)
        try await Self.withConnection(of: server) {
            _ = try await server.call(name: Self.invalidURLToolName, arguments: nil)

            let received = await scripted.receivedElicitationResults.last
            #expect(received?.action == .decline)
            #expect(Self.reason(of: received) == .string(Self.invalidURLReason))
        }
        withExtendedLifetime(scripted) {}
    }

    /// The handler that an `MCPServer` registers on its client holds the
    /// server weakly. A request that arrives after the server is gone gets a
    /// cancel that tells the server why. Before the fix, the cancel had no
    /// `_meta`.
    ///
    /// The order is fixed: the server registers its handler on a client of
    /// the test, and the test releases the server. The test fails before
    /// the connect when the server is not gone. Then the client calls the
    /// eliciting tool, and disconnects also when the call throws.
    @Test("a request that arrives after the MCPServer is gone reaches the server as cancel with the reason")
    func aRequestAfterTheServerIsGoneCancelsWithTheReason() async throws {
        let scripted = ScriptedServer()
        await scripted.addLoopbackTools()
        let client = MCP.Client(
            name: Self.serverName, version: MCPServer.defaultClientVersion,
            capabilities: MCPServer.clientCapabilities(for: .interactive))
        weak var released: MCPServer?
        do {
            let server = MCPTestSupport.makeServer(name: Self.serverName)
            await server.registerElicitationHandler(on: client)
            released = server
        }
        try #require(released == nil, "the MCPServer stayed alive after its last reference went away")
        let transport = try await scripted.startOnInMemoryPair()
        _ = try await client.connect(transport: transport)

        let call = Task { try await client.callTool(name: ScriptedServer.elicitEchoToolName) }
        let outcome = await call.result
        await client.disconnect()
        _ = try outcome.get()

        let received = await scripted.receivedElicitationResults.last
        #expect(received?.action == .cancel)
        #expect(Self.reason(of: received) == .string(Self.hostGoneReason))
    }

    /// A throw of the calling run answers a cancel that tells the server
    /// why. `ToolContext.elicit(_:)` has no path that throws, thus the test
    /// gives a throwing question to the seam of that call, and reads the
    /// wire result that the handler returns to the server. Before the fix,
    /// the cancel had no `_meta`.
    @Test("a throw of the calling run gives the server a cancel with the reason")
    func aThrowOfTheRunCancelsWithTheReason() async {
        let server = MCPTestSupport.makeServer(name: Self.serverName)

        let response = await server.answerThroughRun { throw FailedRun() }

        let result = MCPServer.wireResult(of: response)
        #expect(result.action == .cancel)
        #expect(Self.reason(of: result) == .string(Self.runFailedReason))
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
