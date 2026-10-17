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
@Suite("MCPElicitationTests", .serialized, .ownsTemporaryDirectories)
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

    /// How many elicitation results the scripted server gets for the one
    /// question of a case of two calls in flight.
    private static let oneElicitationResult = 1

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

    /// The reason of the cancel that ends a held URL flow when a newer URL
    /// flow uses the same wire id, spelled out for the same reason.
    private static let replacedByNewerFlowReason = "a newer URL flow used the same elicitation id"

    /// The reason of the cancel of a question that a client of an old
    /// connect delivers after the connect generation moved, spelled out for
    /// the same reason.
    private static let oldConnectionQuestionReason = "the connection to the MCP server ended before the question"

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

    /// Each `url` that `URL(string:)` reads as a URL, but that is not an
    /// absolute `http` or `https` URL with a host: a relative reference, a
    /// `javascript` URL, and an `https` URL with no host.
    private static let notHTTPURLs = ["foo", "javascript:x", "https:///no-host"]

    /// Each absolute `https` URL with a host that goes on to the host: one
    /// with a lowercase scheme, and one with an uppercase scheme, because
    /// URL schemes are not case-sensitive.
    private static let httpURLs = ["https://example.com/verify", "HTTPS://example.com/verify"]

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

    /// A host handler that reports each call on ``call``, waits until the
    /// test opens the release of ``call``, and then accepts the URL question.
    /// Thus a test can act while the handler is busy with a question.
    private struct HeldHandler {
        /// The arrival and the release of each call of the handler.
        let call = HeldCall()

        /// The handler an `MCPServer` is constructed with. A cancel of the
        /// wait for the release answers cancel, and not the accept.
        var handler: MCPServer.ElicitationHandler {
            { [call] _ in
                do {
                    try await call.pass()
                } catch {
                    return .cancel
                }
                return MCPElicitationTests.urlAccept
            }
        }
    }

    /// A sink that records each post in ``recorded``, and holds each end of
    /// a question on ``heldEnd`` after it recorded that end. Thus a test can
    /// act while the run plane ends a question, and the end goes on when the
    /// test opens the release of ``heldEnd``.
    private struct EndHoldingEventSink: OperationEventSink {
        /// The sink that records each post.
        let recorded = RecordingEventSink()

        /// The arrival and the release of each end post.
        let heldEnd = HeldCall()

        /// Records `event`.
        ///
        /// - Parameter event: The posted event.
        func post(event: OperationEvent) async {
            await recorded.post(event: event)
        }

        /// Records the completion of the URL flow `elicitationId`.
        ///
        /// - Parameter elicitationId: The id of the question that completed.
        func post(elicitationCompleted elicitationId: ULID) async {
            await recorded.post(elicitationCompleted: elicitationId)
        }

        /// Records the end of the question `elicitationId`, and then waits
        /// until the test opens the release of ``heldEnd``. A cancel of that
        /// wait lets the end go on, thus a cancelled test does not hold the
        /// run plane.
        ///
        /// - Parameters:
        ///   - elicitationId: The id of the question that ended.
        ///   - response: The answer that the run gets.
        func post(elicitationEnded elicitationId: ULID, response: ElicitationResponse) async {
            await recorded.post(elicitationEnded: elicitationId, response: response)
            try? await heldEnd.pass()
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
    private static func relayContext(on runPlane: RunPlane, sink: any OperationEventSink) -> ToolContext {
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

    /// Calls `tool` on `server` with no arguments under `context`.
    ///
    /// - Parameters:
    ///   - tool: The name of the tool to call.
    ///   - server: The server to call.
    ///   - context: The context to bind around the call.
    /// - Returns: The result of the call.
    /// - Throws: What the call throws.
    private static func callTool(
        _ tool: String, on server: MCPServer, under context: ToolContext
    ) async throws -> CallTool.Result {
        try await ToolContext.$current.withValue(context) {
            try await server.call(name: tool, arguments: nil)
        }
    }

    /// Starts `work`, and waits until the run of `run` records its
    /// elicitation event, or until `work` ends.
    ///
    /// The wait is ``EventRace/start(_:awaiting:cleaningUpOnThrow:)``: it ends
    /// when the recorder of the run records the elicitation event, or when `work`
    /// ends with no question. When no elicitation event came, the test fails
    /// at once. The wait reads no clock and does not poll.
    ///
    /// - Parameters:
    ///   - run: The run whose recorder records the event.
    ///   - work: The work that asks the question under the context of `run`.
    /// - Returns: The task of `work`, and the elicitation event.
    /// - Throws: When `work` ended before the run recorded an elicitation
    ///   event, or when the task is cancelled first.
    private static func startEliciting<Success: Sendable>(
        on run: BoundRun, _ work: @escaping @Sendable () async throws -> Success
    ) async throws -> (task: Task<Success, any Error>, event: OperationEvent) {
        let recorder = run.stub.recorder
        let task = try await EventRace.start(
            work,
            awaiting: { _ = await recorder.waitUntil { events in events.contains { $0.kind == .elicitation } } })
        let event = try #require(
            await recordedOperationEvents(of: run.stub, ofKind: .elicitation).first,
            "the work ended before the run recorded an elicitation event")
        return (task, event)
    }

    /// Starts one call of `tool` on `server` under the context of `run`, and
    /// waits until the run records its elicitation event, or until the call
    /// ends — ``startEliciting(on:_:)`` for one call.
    ///
    /// - Parameters:
    ///   - tool: The name of the eliciting tool.
    ///   - server: The server to call.
    ///   - run: The run that the call asks its question in.
    /// - Returns: The task of the call, and the question.
    /// - Throws: When the call ended before the question came, when the
    ///   event carries no question, or when the task is cancelled first.
    private static func startElicitingCall(
        _ tool: String, on server: MCPServer, in run: BoundRun
    ) async throws -> (call: Task<CallTool.Result, any Error>, request: ElicitationRequest) {
        let context = run.context
        let (call, event) = try await startEliciting(on: run) {
            try await callTool(tool, on: server, under: context)
        }
        return (call, try #require(event.elicitation))
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
        try await startHeldHostFlow(on: server) {
            let generation = await server.connectGeneration
            return await server.answerElicitation(parameters: urlElicitation, generation: generation)
        }
    }

    /// Starts `work`, which makes `server` hold one URL-mode flow, and waits
    /// until `server` holds that flow — see
    /// ``EventRace/start(_:awaiting:cleaningUpOnThrow:)``. When no flow is held, the
    /// test fails at once. When the wait throws, a held flow ends before the
    /// throw, thus `work` does not stay open.
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
        let flow = try await EventRace.start(
            work,
            awaiting: {
                await server.waitUntilHostElicitationHeld(elicitationId: ScriptedServer.elicitURLElicitationId)
            },
            cleaningUpOnThrow: { _ in await server.complete(elicitationId: ScriptedServer.elicitURLElicitationId) })
        try #require(
            await server.pendingHostElicitationIds == [ScriptedServer.elicitURLElicitationId],
            "the work ended before the server held the URL flow")
        return flow
    }

    /// Delivers ``urlElicitation`` to `server` under `generation`, waits until
    /// `gate` opened, and fails the test at once when the answer ended first
    /// — see ``EventRace/watch(_:untilOpen:orFail:sourceLocation:)``.
    ///
    /// - Parameters:
    ///   - server: The server that answers the question.
    ///   - generation: The connect generation of the question.
    ///   - gate: The gate that the answer opens when it gets to its step.
    ///   - failure: What the failure of the test says when `gate` is not
    ///     open.
    /// - Returns: The task of the answer that `server` gives.
    /// - Throws: When the answer ended before `gate` opened, or when the
    ///   task is cancelled first.
    private static func startURLAnswer(
        on server: MCPServer, generation: Int, untilOpen gate: TestGate, orFail failure: Comment
    ) async throws -> Task<CreateElicitation.Result, any Error> {
        try await EventRace.watch(
            { await server.answerElicitation(parameters: urlElicitation, generation: generation) },
            untilOpen: gate, orFail: failure
        ).task
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
    /// The wait for the question is
    /// ``EventRace/start(_:awaiting:cleaningUpOnThrow:)``:
    /// it ends when the question reached `sink`, or when the call ended with
    /// no question. When no question came, the test fails at once.
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
        let call = try await EventRace.start(
            { try await callTool(ScriptedServer.elicitURLToolName, on: server, under: context) },
            awaiting: { await sink.waitUntilEvent { $0.kind == .elicitation } })
        let request = try #require(
            await sink.events.first(where: { $0.kind == .elicitation })?.elicitation,
            "the call ended before the question reached the sink")
        let delivery = await runPlane.respond(elicitationId: request.elicitationId, urlAccept)
        try #require(delivery == .acceptedAwaitingCompletion)
        return ContextURLFlow(call: call, request: request)
    }

    /// One URL question that `MCPServer.answerElicitation(parameters:generation:)`
    /// sent to the run of a bound context.
    private struct ContextURLQuestion {
        /// The task of the answer that the server gives on the wire.
        let answer: Task<CreateElicitation.Result, any Error>

        /// The question, with the `ToolContext` id that the server chose.
        let request: ElicitationRequest
    }

    /// Delivers ``urlElicitation`` to `server` with the current connect
    /// generation, and waits until a new question reaches `sink`: a question
    /// whose id is not in `earlier`. The call in flight of a context over
    /// `sink` must be the one run that a question can go to.
    ///
    /// The wait for the question is
    /// ``EventRace/start(_:awaiting:cleaningUpOnThrow:)``:
    /// it ends when the new question reached `sink`, or when the answer ended
    /// with no question. When no new question came, the test fails at once.
    ///
    /// - Parameters:
    ///   - server: The connected server.
    ///   - sink: The sink of the context of the call in flight.
    ///   - earlier: The id of each question that reached `sink` before.
    /// - Returns: The question.
    /// - Throws: When the answer ended before the question came, or when the
    ///   task is cancelled first.
    private static func startContextURLQuestion(
        on server: MCPServer, sink: RecordingEventSink, after earlier: [ULID]
    ) async throws -> ContextURLQuestion {
        let isNew: @Sendable (ElicitationRequest) -> Bool = { !earlier.contains($0.elicitationId) }
        let generation = await server.connectGeneration
        let answer = try await EventRace.start(
            { await server.answerElicitation(parameters: urlElicitation, generation: generation) },
            awaiting: { await sink.waitUntilEvent { $0.elicitation.map(isNew) ?? false } })
        let request = try #require(
            await sink.events.compactMap(\.elicitation).first(where: isNew),
            "the answer ended before the question reached the sink")
        return ContextURLQuestion(answer: answer, request: request)
    }

    // MARK: - Case 1: a bound context answers

    @Test("the answer the test delivers through the session reaches elicitEcho", arguments: transports)
    func theSessionAnswerReachesTheTool(kind: MCPTransportKind) async throws {
        let (scripted, server) = try await Self.connected(over: kind)
        try await MCPTestSupport.withConnection(of: server) {
            try await BoundRun.with { run in
                let context = run.context
                let (call, event) = try await Self.startEliciting(on: run) {
                    try await Self.callTool(ScriptedServer.elicitEchoToolName, on: server, under: context)
                }
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
        try await MCPTestSupport.withConnection(of: server) {
            try await BoundRun.with { run in
                let (call, request) = try await Self.startElicitingCall(
                    ScriptedServer.elicitURLToolName, on: server, in: run)
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
    /// for ever. The wait for the question also ends when the call ends with
    /// no question (``startContextURLFlow(on:runPlane:sink:)``). The sink
    /// posts the completion in a task of the run plane, thus the test waits
    /// for that post as an event. That wait also ends when the flow ends
    /// with no completion: the drop then ends the flow with a cancel, and the
    /// check of the completed flows fails.
    @Test("a wire completion of a URL flow under a context completes the flow on the run plane, one time")
    func aWireCompletionUnderAContextCompletesTheFlow() async throws {
        let (scripted, server) = try await Self.connected(over: .inMemory)
        try await MCPTestSupport.withConnection(of: server) {
            let runPlane = RunPlane(userPresence: .interactive)
            let sink = RecordingEventSink()
            let flow = try await Self.startContextURLFlow(on: server, runPlane: runPlane, sink: sink)

            try await scripted.sendElicitationCompleteThenDrop(elicitationId: ScriptedServer.elicitURLElicitationId)
            _ = await flow.call.result
            let lateCompletion = await runPlane.complete(elicitationId: flow.request.elicitationId)
            await sink.waitUntilElicitationSettled()

            #expect(lateCompletion == .noPendingElicitation)
            #expect(await sink.completedElicitationIds == [flow.request.elicitationId])
        }
        withExtendedLifetime(scripted) {}
    }

    @Test("a runCode snippet suspends on the elicitation and returns the session answer over the HTTP loopback")
    func aSnippetSuspendsOnTheElicitationAndReturnsTheAnswer() async throws {
        let (scripted, server) = try await Self.connected(over: .http)
        try await MCPTestSupport.withConnection(of: server) {
            let registry = try await MultiTool.Builder().withMCP(servers: [server]).buildRegistry()
            let multiTool = MultiTool(registry: registry)
            try await BoundRun.with { run in
                let context = run.context
                let (snippet, event) = try await Self.startEliciting(on: run) {
                    try await ToolContext.$current.withValue(context) {
                        try await multiTool.call(arguments: RunCodeArguments(code: Self.elicitEchoSnippet))
                    }
                }
                let request = try #require(event.elicitation)
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
        try await MCPTestSupport.withConnection(of: server) {
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
        try await MCPTestSupport.withConnection(of: server) {
            let tool = try await Self.tool(named: ScriptedServer.elicitEchoToolName, on: server)

            let output = try await Self.bareCall(tool)

            #expect(output.contains(Self.scriptedAnswer))
            #expect(output.contains(Self.acceptText))
            let requests = await probe.requests
            #expect(requests.count == Self.oneHandlerCall)
            #expect(requests.first?.mode == .form)
        }
        withExtendedLifetime(scripted) {}
    }

    @Test("with no context bound, a URL-mode accept of the handler ends on MCPServer.complete(elicitationId:)")
    func theHandlerURLAcceptEndsOnComplete() async throws {
        let probe = HandlerProbe(responding: Self.urlAccept)
        let (scripted, server) = try await Self.connected(over: .inMemory, elicitationHandler: probe.handler)
        try await MCPTestSupport.withConnection(of: server) {
            let tool = try await Self.tool(named: ScriptedServer.elicitURLToolName, on: server)

            let call = try await Self.startHeldHostFlow(on: server) { try await Self.bareCall(tool) }
            #expect(await server.inFlightCalls.count == Self.oneCallInFlight)
            await server.complete(elicitationId: ScriptedServer.elicitURLElicitationId)
            let output = try await call.value

            #expect(output.contains(Self.acceptText))
            #expect(await server.pendingHostElicitationIds.isEmpty)
        }
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
        try await MCPTestSupport.withConnection(of: server) {
            let tool = try await Self.tool(named: ScriptedServer.elicitURLToolName, on: server)

            let call = try await Self.startHeldHostFlow(on: server) { try await Self.bareCall(tool) }
            try await scripted.sendElicitationCompleteThenDrop(elicitationId: ScriptedServer.elicitURLElicitationId)
            _ = await call.result
            let heldAfterTheCall = await server.pendingHostElicitationIds
            // A flow that is still held ends here, thus no continuation stays.
            await server.complete(elicitationId: ScriptedServer.elicitURLElicitationId)

            #expect(heldAfterTheCall.isEmpty)
        }
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

    /// A URL accept of the handler that returns after a disconnect or a new
    /// connect moved the connect generation belongs to a connection that
    /// ended. The end of the connection ran before the accept, thus nothing
    /// can end a flow that the server holds then. The accept ends at once
    /// with a cancel and a reason, and the server does not hold the flow.
    /// Before the fix, the server held the late flow under the new
    /// generation, and it stayed held until the next end of a connection.
    ///
    /// The order is fixed. The question reaches the handler, and the test
    /// waits for the first of two events: the handler was called, or the
    /// answer ended — see ``startURLAnswer(on:generation:untilOpen:orFail:)``.
    /// When the handler was not called, the test fails at once. Then the connection
    /// ends. Then the test lets the handler return the accept, and waits for
    /// the first of two events: the server holds the flow, or the answer
    /// ended. The test reads the held flows before it waits for the answer,
    /// and it completes a flow that is still held. Thus a flow that stays
    /// held fails the test, and no wait stays open.
    @Test(
        "a URL accept of the handler after the end of its connection gets cancel with a reason, and is not held",
        arguments: ConnectionEnd.allCases)
    func aLateHandlerAcceptAfterTheEndOfItsConnectionCancels(end: ConnectionEnd) async throws {
        let handler = HeldHandler()
        let server = MCPTestSupport.makeServer(name: Self.serverName, elicitationHandler: handler.handler)
        defer { handler.call.release.open() }
        let generation = await server.connectGeneration
        let answer = try await Self.startURLAnswer(
            on: server, generation: generation, untilOpen: handler.call.arrival,
            orFail: "the answer ended before the question reached the handler")

        await Self.endConnection(of: server, with: end)
        let lateAnswer = try await EventRace.start(
            {
                handler.call.release.open()
                return try await answer.value
            },
            awaiting: {
                await server.waitUntilHostElicitationHeld(elicitationId: ScriptedServer.elicitURLElicitationId)
            })

        let heldAfterTheAccept = await server.pendingHostElicitationIds
        // A flow that is still held ends here, thus no continuation stays.
        await server.complete(elicitationId: ScriptedServer.elicitURLElicitationId)
        let result = try await lateAnswer.value
        #expect(heldAfterTheAccept.isEmpty)
        #expect(result.action == .cancel)
        #expect(Self.reason(of: result) == .string(Self.connectionEndedReason))
    }

    /// A second URL flow of the handler under a wire id that this actor still
    /// holds ends the earlier flow. The completion of the earlier flow never
    /// came, thus the earlier flow sends cancel with a reason to the server,
    /// and not accept. Before the fix, the earlier flow sent accept: the run
    /// read a user accept that the user never gave.
    ///
    /// The order is fixed. The server holds the first flow. The test starts
    /// the second flow, and waits for the first of two events: the first
    /// flow ended, or the second flow ended. Each of the two events can
    /// occur, thus the wait always ends. The first flow ends only in the
    /// step of the actor that holds the second flow, thus after the wait one
    /// flow is held. The test completes that flow, and then reads the two
    /// answers. When the gate wait throws, the test ends each held flow
    /// before the throw.
    @Test("with no context bound, a second URL flow under a held wire id ends the earlier flow with cancel and a reason")
    func aSecondFlowUnderAHeldWireIdCancelsTheEarlierFlow() async throws {
        let probe = HandlerProbe(responding: Self.urlAccept)
        let server = MCPTestSupport.makeServer(name: Self.serverName, elicitationHandler: probe.handler)
        let first = try await Self.startHeldHostFlow(on: server)
        let firstEvent = TestGate()
        let second = Task {
            defer { firstEvent.open() }
            let generation = await server.connectGeneration
            return await server.answerElicitation(parameters: Self.urlElicitation, generation: generation)
        }
        let firstEnded = Task {
            _ = await first.result
            firstEvent.open()
        }
        do {
            try await firstEvent.wait()
        } catch {
            await server.disconnect()
            await firstEnded.value
            _ = await second.value
            throw error
        }

        await server.complete(elicitationId: ScriptedServer.elicitURLElicitationId)

        let firstResult = try await first.value
        let secondResult = await second.value
        await firstEnded.value
        #expect(firstResult.action == .cancel)
        #expect(Self.reason(of: firstResult) == .string(Self.replacedByNewerFlowReason))
        #expect(secondResult.action == .accept)
        #expect(await server.pendingHostElicitationIds.isEmpty)
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
        try await MCPTestSupport.withConnection(of: server) {
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

    /// A URL question of a context first ends an earlier question under the
    /// same wire id, and that end suspends. When a disconnect or a new
    /// connect moves the connect generation during that end, the question
    /// belongs to a connection that ended: the end of the connection ran
    /// before the question has an entry, thus nothing can end the question
    /// then. The question ends at once with a cancel and a reason, it gets no
    /// entry, and it never reaches the run. Before the fix, the question got
    /// an entry of the old generation and opened on the run, and it stayed
    /// open until the next end of a connection.
    ///
    /// The order is fixed. A call under the context is in flight, thus its
    /// run is the one run that a question can go to. The earlier question
    /// reaches the run, and the run accepts it. Then the newer question
    /// starts, and the test waits for the first of two events: the sink
    /// holds the end post of the earlier question, or the newer answer ended
    /// — see ``startURLAnswer(on:generation:untilOpen:orFail:)``. When the end
    /// post is not held, the test fails at once. The held call then ends, and the
    /// connection ends. Then the test lets the end post go on, and waits for
    /// the first of two events: the newer question reached the sink, or the
    /// newer answer ended. The test reads the entries before it waits for the
    /// answers, and it declines a newer question that reached the run. Thus
    /// a question that opens fails the test, and no wait stays open.
    @Test(
        "a URL question of a context whose connection ends while it replaces an earlier question gets cancel",
        arguments: ConnectionEnd.allCases)
    func aContextQuestionWhoseConnectionEndsDuringTheReplacementCancels(end: ConnectionEnd) async throws {
        let (scripted, server, held) = try await Self.connectedForTwoCalls(over: .inMemory)
        try await MCPTestSupport.withConnection(of: server) {
            let runPlane = RunPlane(userPresence: .interactive)
            let sink = EndHoldingEventSink()
            defer { sink.heldEnd.release.open() }
            let context = Self.relayContext(on: runPlane, sink: sink)
            let generation = await server.connectGeneration
            let (earlier, newer) = try await Self.whileHolding(held, under: context, on: server) {
                let earlier = try await Self.startContextURLQuestion(on: server, sink: sink.recorded, after: [])
                let delivery = await runPlane.respond(elicitationId: earlier.request.elicitationId, Self.urlAccept)
                try #require(delivery == .acceptedAwaitingCompletion)
                let newer = try await Self.startURLAnswer(
                    on: server, generation: generation, untilOpen: sink.heldEnd.arrival,
                    orFail: "the newer answer ended before the end of the earlier question")
                return (earlier, newer)
            }

            await Self.endConnection(of: server, with: end)
            let earlierId = earlier.request.elicitationId
            let isNewer: @Sendable (ElicitationRequest) -> Bool = { $0.elicitationId != earlierId }
            let lateAnswer = try await EventRace.start(
                {
                    sink.heldEnd.release.open()
                    return try await newer.value
                },
                awaiting: { await sink.recorded.waitUntilEvent { $0.elicitation.map(isNewer) ?? false } })

            let newerQuestion = await sink.recorded.events.compactMap(\.elicitation).first(where: isNewer)
            let entriesAfterTheEnd = await server.pendingContextElicitations.count
            // A newer question that reached the run ends here, thus no answer stays open.
            if let newerQuestion {
                _ = await runPlane.respond(elicitationId: newerQuestion.elicitationId, .decline)
            }
            let newerResult = try await lateAnswer.value
            let earlierResult = try await earlier.answer.value
            #expect(newerQuestion?.elicitationId == nil)
            #expect(entriesAfterTheEnd == 0)
            #expect(newerResult.action == .cancel)
            #expect(Self.reason(of: newerResult) == .string(Self.connectionEndedReason))
            #expect(earlierResult.action == .cancel)
            #expect(Self.reason(of: earlierResult) == .string(Self.replacedByNewerFlowReason))
        }
        withExtendedLifetime(scripted) {}
    }

    /// A second URL question of a bound context under a wire id that an open
    /// question of a context already uses gets the entry of that id. The
    /// earlier question ends at once with a cancel and a reason, the same
    /// rule as the held flows of the handler. Thus a wire completion of the
    /// id ends the newer question, and a disconnect can end it too, because
    /// its entry is in the map. Before the fix, the newer question got no
    /// entry: the wire completion went to the earlier question, and nothing
    /// but the run could end the newer question.
    ///
    /// The order is fixed. A call under the context is in flight, thus its
    /// run is the one run that a question can go to. The earlier question
    /// reaches the run, and the run accepts it. Then the newer question
    /// reaches the run, and the run accepts it. The test reads the entry and
    /// the ended questions, and relays a wire completion of the id. Then the
    /// test completes on the run plane each question that is still open,
    /// thus no answer stays open, and then it reads the two answers.
    @Test("a second URL question of a context under a wire id in use ends the earlier question, and gets the entry")
    func aSecondContextQuestionUnderAWireIdInUseReplacesTheEarlierQuestion() async throws {
        let (scripted, server, held) = try await Self.connectedForTwoCalls(over: .inMemory)
        try await MCPTestSupport.withConnection(of: server) {
            let runPlane = RunPlane(userPresence: .interactive)
            let sink = RecordingEventSink()
            let context = Self.relayContext(on: runPlane, sink: sink)
            try await Self.whileHolding(held, under: context, on: server) {
                let generation = await server.connectGeneration
                let earlier = try await Self.startContextURLQuestion(on: server, sink: sink, after: [])
                let earlierDelivery = await runPlane.respond(elicitationId: earlier.request.elicitationId, Self.urlAccept)
                let newer = try await Self.startContextURLQuestion(
                    on: server, sink: sink, after: [earlier.request.elicitationId])
                let newerDelivery = await runPlane.respond(elicitationId: newer.request.elicitationId, Self.urlAccept)
                let entry = await server.pendingContextElicitations[ScriptedServer.elicitURLElicitationId]
                let endedAfterTheNewer = await sink.endedElicitations

                await server.complete(elicitationId: ScriptedServer.elicitURLElicitationId, generation: generation)

                // A question that is still open ends here, thus no answer stays open.
                let lateNewerCompletion = await runPlane.complete(elicitationId: newer.request.elicitationId)
                _ = await runPlane.complete(elicitationId: earlier.request.elicitationId)
                let earlierResult = try await earlier.answer.value
                let newerResult = try await newer.answer.value
                #expect(earlierDelivery == .acceptedAwaitingCompletion)
                #expect(newerDelivery == .acceptedAwaitingCompletion)
                #expect(entry?.id == newer.request.elicitationId)
                #expect(entry?.generation == generation)
                #expect(
                    endedAfterTheNewer == [
                        RecordingEventSink.EndedElicitation(
                            elicitationId: earlier.request.elicitationId,
                            response: .cancel(reason: Self.replacedByNewerFlowReason))
                    ])
                #expect(lateNewerCompletion == .noPendingElicitation)
                #expect(earlierResult.action == .cancel)
                #expect(Self.reason(of: earlierResult) == .string(Self.replacedByNewerFlowReason))
                #expect(newerResult.action == .accept)
                #expect(await server.pendingContextElicitations.isEmpty)
            }
        }
        withExtendedLifetime(scripted) {}
    }

    /// A URL question of a bound context under a wire id that a held flow of
    /// the handler still uses ends that held flow, and gets the entry of the
    /// id. The held flow sends cancel with a reason to the server, and a wire
    /// completion of the id ends the question of the context. Before the
    /// fix, the question replaced nothing: the completion ended the held flow
    /// first, and the question of the context waited until the end of its
    /// connection.
    ///
    /// The order is fixed. With no call in flight, the handler accepts the
    /// flow, and the server holds it. Then a call under the context is in
    /// flight, thus its run is the one run that a question can go to, and the
    /// question reaches that run. The test reads the held flows before it
    /// waits for an answer: when the flow is still held, the test fails at
    /// once, and the disconnect ends each open flow. Then the run accepts
    /// the question, the test relays a wire completion of the id, and it
    /// reads the two answers.
    @Test("a URL question of a context under the wire id of a held flow of the handler ends the held flow")
    func aContextQuestionUnderAHeldWireIdReplacesTheHeldFlow() async throws {
        let probe = HandlerProbe(responding: Self.urlAccept)
        let (scripted, server, held) = try await Self.connectedForTwoCalls(
            over: .inMemory, elicitationHandler: probe.handler)
        try await MCPTestSupport.withConnection(of: server) {
            let runPlane = RunPlane(userPresence: .interactive)
            let sink = RecordingEventSink()
            let context = Self.relayContext(on: runPlane, sink: sink)
            let heldFlow = try await Self.startHeldHostFlow(on: server)
            try await Self.whileHolding(held, under: context, on: server) {
                let generation = await server.connectGeneration
                let question = try await Self.startContextURLQuestion(on: server, sink: sink, after: [])
                try #require(
                    await server.pendingHostElicitationIds.isEmpty,
                    "the question of the context did not end the held flow of the handler")
                let delivery = await runPlane.respond(elicitationId: question.request.elicitationId, Self.urlAccept)
                let entry = await server.pendingContextElicitations[ScriptedServer.elicitURLElicitationId]

                await server.complete(elicitationId: ScriptedServer.elicitURLElicitationId, generation: generation)

                let heldResult = try await heldFlow.value
                let questionResult = try await question.answer.value
                #expect(delivery == .acceptedAwaitingCompletion)
                #expect(entry?.id == question.request.elicitationId)
                #expect(heldResult.action == .cancel)
                #expect(Self.reason(of: heldResult) == .string(Self.replacedByNewerFlowReason))
                #expect(questionResult.action == .accept)
                #expect(await server.pendingContextElicitations.isEmpty)
            }
        }
        withExtendedLifetime(scripted) {}
    }

    /// A URL flow of the handler under a wire id that an open question of a
    /// bound context still uses ends that question, and the server holds the
    /// newer flow. The question of the context sends cancel with a reason to
    /// the server, and a wire completion of the id ends the held flow. Before
    /// the fix, the held flow replaced nothing: the completion ended the held
    /// flow, and the question of the context waited until the end of its
    /// connection.
    ///
    /// The order is fixed. A call under the context is in flight, thus its
    /// run is the one run that a question can go to, and the question reaches
    /// that run. Then the call ends, thus no call is in flight. The run
    /// accepts the question, and then the handler accepts the newer flow
    /// under the same wire id. The test reads the entries of the context
    /// before it waits for an answer: when the question still has its entry,
    /// the test fails at once, and the disconnect ends each open flow. Then
    /// the test relays a wire completion of the id, and it reads the two
    /// answers.
    @Test("a held flow of the handler under the wire id of an open question of a context ends the question")
    func aHeldFlowUnderTheWireIdOfAContextQuestionReplacesTheQuestion() async throws {
        let probe = HandlerProbe(responding: Self.urlAccept)
        let (scripted, server, held) = try await Self.connectedForTwoCalls(
            over: .inMemory, elicitationHandler: probe.handler)
        try await MCPTestSupport.withConnection(of: server) {
            let runPlane = RunPlane(userPresence: .interactive)
            let sink = RecordingEventSink()
            let context = Self.relayContext(on: runPlane, sink: sink)
            let generation = await server.connectGeneration
            let question = try await Self.whileHolding(held, under: context, on: server) {
                try await Self.startContextURLQuestion(on: server, sink: sink, after: [])
            }
            let delivery = await runPlane.respond(elicitationId: question.request.elicitationId, Self.urlAccept)
            let heldFlow = try await Self.startHeldHostFlow(on: server)
            try #require(
                await server.pendingContextElicitations[ScriptedServer.elicitURLElicitationId] == nil,
                "the held flow of the handler did not end the question of the context")
            let endedAfterTheHold = await sink.endedElicitations

            await server.complete(elicitationId: ScriptedServer.elicitURLElicitationId, generation: generation)

            let questionResult = try await question.answer.value
            let heldResult = try await heldFlow.value
            #expect(delivery == .acceptedAwaitingCompletion)
            #expect(
                endedAfterTheHold == [
                    RecordingEventSink.EndedElicitation(
                        elicitationId: question.request.elicitationId,
                        response: .cancel(reason: Self.replacedByNewerFlowReason))
                ])
            #expect(questionResult.action == .cancel)
            #expect(Self.reason(of: questionResult) == .string(Self.replacedByNewerFlowReason))
            #expect(heldResult.action == .accept)
            #expect(await server.pendingHostElicitationIds.isEmpty)
            #expect(await server.pendingContextElicitations.isEmpty)
        }
        withExtendedLifetime(scripted) {}
    }

    /// A URL question that a client of an old connect delivers after a new
    /// connect moved the generation belongs to a connection that ended. It
    /// ends at once with a cancel and a reason, and it never opens a question
    /// on the run of the new connection. Before the fix, the question opened
    /// on that run under the generation of the new connection: a completion
    /// that the old transport relays was dropped, and the end of the old
    /// connection skipped the question.
    ///
    /// The order is fixed. The server connects two times. A call under the
    /// context of a run is in flight on the second connection, thus that
    /// run is the one run that a question can go to. Then the test delivers
    /// the question with the generation of the first connect. The sink of
    /// the run declines each question it gets at once, thus a question that
    /// reaches the run ends with no step of the test, and no wait stays open.
    @Test("a URL question of an old client gets cancel with a reason, and never reaches the run of the new connection")
    func aQuestionOfAnOldClientDoesNotReachTheRun() async throws {
        let reconnected = try await Self.reconnectedForTwoCalls()
        let server = reconnected.server
        try await MCPTestSupport.withConnection(of: server) {
            let holding = AnsweringRun(
                session: ULID(), runPlane: RunPlane(userPresence: .interactive),
                completionToken: Self.holdingRunToken, response: .decline)

            let result = try await Self.whileHolding(reconnected.held, under: holding.context, on: server) {
                await server.answerElicitation(
                    parameters: Self.urlElicitation, generation: reconnected.earlierGeneration)
            }

            #expect(result.action == .cancel)
            #expect(Self.reason(of: result) == .string(Self.oldConnectionQuestionReason))
            #expect(await holding.sink.questions.isEmpty)
            #expect(await server.pendingContextElicitations.isEmpty)
        }
        withExtendedLifetime((reconnected.earlier, reconnected.scripted)) {}
    }

    /// A question that a client of an old connect delivers after a
    /// disconnect or a new connect moved the generation gets the same answer
    /// on the path of the host's handler: a cancel and a reason at once. The
    /// handler is never called. Before the fix, the handler answered the
    /// question of a connection that ended.
    ///
    /// The order is fixed: the connection ends, and then the test delivers
    /// the question with the generation from before the end. The handler
    /// declines at once, thus a question that reaches it ends with no step
    /// of the test.
    @Test(
        "a question of an old client gets cancel with a reason, and never reaches the host's handler",
        arguments: ConnectionEnd.allCases)
    func aQuestionOfAnOldClientDoesNotReachTheHandler(end: ConnectionEnd) async throws {
        let probe = HandlerProbe(responding: .decline)
        let server = MCPTestSupport.makeServer(name: Self.serverName, elicitationHandler: probe.handler)
        let earlierGeneration = await server.connectGeneration

        await Self.endConnection(of: server, with: end)
        let result = await server.answerElicitation(parameters: Self.urlElicitation, generation: earlierGeneration)

        #expect(result.action == .cancel)
        #expect(Self.reason(of: result) == .string(Self.oldConnectionQuestionReason))
        #expect(await probe.requests.isEmpty)
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
    /// recorded the wait, or the wait ended — see
    /// ``EventRace/start(_:awaiting:cleaningUpOnThrow:)``. Each event can occur, thus
    /// that wait always ends. Then the test cancels the wait and reads its
    /// result. When the gate wait throws, the test ends the wait before the
    /// throw.
    @Test("a cancel during a wait for the hold of a URL flow ends the wait with false")
    func aCancelDuringTheWaitEndsIt() async throws {
        let server = MCPTestSupport.makeServer(name: Self.serverName)
        let wait = try await EventRace.start(
            { await server.waitUntilHostElicitationHeld(elicitationId: ScriptedServer.elicitURLElicitationId) },
            awaiting: {
                await server.waitUntilHostElicitationHeldWaitIsRecorded(
                    elicitationId: ScriptedServer.elicitURLElicitationId)
            },
            cleaningUpOnThrow: EventRace.endWait)
        let waitersBeforeTheCancel = await server.hostElicitationHeldWaiters.count

        wait.cancel()
        let endedOnTheHold = try await wait.value

        #expect(waitersBeforeTheCancel == 1)
        #expect(endedOnTheHold == false)
        #expect(await server.hostElicitationHeldWaiters.isEmpty)
    }

    // MARK: - Case 3: nothing answers

    @Test("with no context and no handler, elicitEcho gets cancel and the call returns without a throw")
    func noContextAndNoHandlerCancels() async throws {
        let (scripted, server) = try await Self.connected(over: .inMemory)
        try await MCPTestSupport.withConnection(of: server) {
            let tool = try await Self.tool(named: ScriptedServer.elicitEchoToolName, on: server)

            let output = try await Self.bareCall(tool)

            #expect(output.contains(Self.cancelText))
        }
        withExtendedLifetime(scripted) {}
    }

    // MARK: - Precedence

    @Test("with both a context and a handler, the context answers and the handler is never called")
    func theContextWinsOverTheHandler() async throws {
        let probe = HandlerProbe(responding: Self.urlAccept)
        let (scripted, server) = try await Self.connected(over: .inMemory, elicitationHandler: probe.handler)
        try await MCPTestSupport.withConnection(of: server) {
            try await BoundRun.with { run in
                let (call, request) = try await Self.startElicitingCall(
                    ScriptedServer.elicitEchoToolName, on: server, in: run)
                await run.session.respond(
                    elicitationId: request.elicitationId.description, response: Self.scriptedAccept)
                let result = try await call.value

                #expect(Self.answer(in: result) == Self.scriptedAnswer)
                #expect(await probe.requests.count == Self.noHandlerCalls)
            }
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
            self.init(
                session: sessionID, runPlane: runPlane, completionToken: completionToken,
                response: .accept(content: [ScriptedServer.elicitEchoAnswerField: .string(answer)]))
        }

        /// Makes a run of the session `sessionID` on `runPlane`, with the
        /// completion token `completionToken`. Its sink answers each question
        /// with `response`.
        ///
        /// - Parameters:
        ///   - sessionID: The session of the run.
        ///   - runPlane: The run plane of the session.
        ///   - completionToken: The completion token of the run.
        ///   - response: The answer the sink gives.
        init(session sessionID: ULID, runPlane: RunPlane, completionToken: String, response: ElicitationResponse) {
            sink = AnsweringEventSink(answeringOn: runPlane, with: response)
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
    ///   - elicitationHandler: The host's answerer, or `nil`.
    ///   - logger: The logger of the connected server.
    /// - Returns: The scripted server, which the test keeps alive, the
    ///   connected server, and the held tool.
    /// - Throws: What the connect throws.
    private static func connectedForTwoCalls(
        over kind: MCPTransportKind, elicitationHandler: MCPServer.ElicitationHandler? = nil,
        logger: Logger = MCPServer.defaultLogger
    ) async throws -> (scripted: ScriptedServer, server: MCPServer, held: HeldScriptedTool) {
        let (scripted, held) = await scriptedForTwoCalls()
        let server = try await MCPTestSupport.connectedMCPServer(
            to: scripted, over: kind, name: serverName, elicitationHandler: elicitationHandler, logger: logger)
        return (scripted, server, held)
    }

    /// A fresh scripted server that serves the held tool, the two tools that
    /// order calls around it, the loopback tools, the tool that echoes its
    /// progress token, and the tool that sends a token of no call. No server
    /// is connected against it yet.
    ///
    /// - Returns: The scripted server, and the held tool that it serves.
    private static func scriptedForTwoCalls() async -> (scripted: ScriptedServer, held: HeldScriptedTool) {
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
        return (scripted, held)
    }

    /// A server that connected two times: first against an empty scripted
    /// server, and then against the scripted server of
    /// ``scriptedForTwoCalls()``. The second connect moved the connect
    /// generation, thus a client of the first connect is an old client.
    private struct ReconnectedServer {
        /// The scripted server of the first connect, which the test keeps
        /// alive.
        let earlier: ScriptedServer

        /// The scripted server of the second connect, which the test keeps
        /// alive.
        let scripted: ScriptedServer

        /// The held tool that ``scripted`` serves.
        let held: HeldScriptedTool

        /// The server, connected over the second connect.
        let server: MCPServer

        /// The connect generation of the first connect: the generation that
        /// the client of an old connection has.
        let earlierGeneration: Int
    }

    /// Connects a server named ``serverName`` two times over the in-memory
    /// transport — see ``ReconnectedServer``.
    ///
    /// - Returns: The server and the facts of its two connects.
    /// - Throws: What a connect throws.
    private static func reconnectedForTwoCalls() async throws -> ReconnectedServer {
        let earlier = ScriptedServer()
        let (scripted, held) = await scriptedForTwoCalls()
        let server = try await MCPTestSupport.connectedMCPServer(to: earlier, over: .inMemory, name: serverName)
        let earlierGeneration = await server.connectGeneration
        do {
            try await server.connect(via: try await MCPTestSupport.clientTransport(serving: scripted, over: .inMemory))
        } catch {
            // The test gets no server when the second connect throws, thus
            // this helper closes the connection before the throw.
            await server.disconnect()
            throw error
        }
        return ReconnectedServer(
            earlier: earlier, scripted: scripted, held: held, server: server, earlierGeneration: earlierGeneration)
    }

    /// Runs `body` while a call of `held` under `holding` is in flight on
    /// `server`, and returns what `body` returned.
    ///
    /// The order is fixed. The held call starts, and the test waits for the
    /// first of two events: the call arrived at the server, or the call
    /// ended — see ``EventRace/start(_:awaiting:cleaningUpOnThrow:)``. Each of the two
    /// events can occur, thus the wait always ends. When the call did not
    /// arrive, the test fails at once. Then `body` runs. On each path, also
    /// when the wait or `body` throws, the test releases the held call and
    /// waits until it ended, thus no call stays held.
    ///
    /// - Parameters:
    ///   - held: The held tool.
    ///   - holding: The context of the held call.
    ///   - server: The connected server.
    ///   - body: The work of the test while the held call is in flight.
    /// - Returns: What `body` returned.
    /// - Throws: When the held call ended before it arrived, what `body`
    ///   threw, or what the held call threw.
    private static func whileHolding<Result>(
        _ held: HeldScriptedTool, under holding: ToolContext, on server: MCPServer,
        _ body: () async throws -> Result
    ) async throws -> Result {
        let holdingCall = try await EventRace.start(
            { try await callTool(held.name, on: server, under: holding) },
            awaiting: { try? await held.waitForArrival() },
            cleaningUpOnThrow: { call in await releaseHeldCall(held, call) })
        do {
            try #require(held.hasArrived, "the held call ended before it arrived at the server")
            let result = try await body()
            _ = try await releaseHeldCall(held, holdingCall).get()
            return result
        } catch {
            await releaseHeldCall(held, holdingCall)
            throw error
        }
    }

    /// Releases `held`, and waits until `call` ended — the one
    /// release-then-await teardown of a held call in this suite. A second
    /// release of `held` changes nothing, thus a caller can call this again
    /// when the first call of it threw.
    ///
    /// - Parameters:
    ///   - held: The held tool.
    ///   - call: The task of the call of `held`.
    /// - Returns: The result of `call`.
    @discardableResult
    private static func releaseHeldCall<Success: Sendable>(
        _ held: HeldScriptedTool, _ call: Task<Success, any Error>
    ) async -> Result<Success, any Error> {
        await held.release()
        return await call.result
    }

    /// Calls `tool` on `server` under `asking`, while a call of `held` under
    /// `holding` is in flight, and returns the result of `tool`.
    ///
    /// The order is fixed. The held call starts, and the test waits until it
    /// arrived at the server — see
    /// ``whileHolding(_:under:on:_:)``. Thus the held call is in flight
    /// before the second call starts. That wait also ends when the held call
    /// ends with no arrival, and then the test fails at once.
    ///
    /// Then the second call starts, and the test waits for the first of two
    /// events: the second call ends, or `scripted` got the answer to the
    /// question of the second call — see
    /// ``EventRace/start(_:awaiting:cleaningUpOnThrow:)``. After the answer, the link
    /// of the question is done, thus the held call is not necessary any more.
    /// Then the test releases the held call, on each path. Thus the release
    /// does not depend on the return of the second call. Last, the test
    /// awaits the second call.
    ///
    /// - Parameters:
    ///   - tool: The name of the tool of the second call.
    ///   - asking: The context of the second call.
    ///   - held: The held tool of the first call.
    ///   - holding: The context of the first call.
    ///   - server: The connected server.
    ///   - scripted: The scripted server that `server` is connected to.
    /// - Returns: The result of the second call.
    /// - Throws: When the held call ended before it arrived, what the second
    ///   call throws, or what the held call throws.
    private static func call(
        _ tool: String, under asking: ToolContext,
        whileHolding held: HeldScriptedTool, under holding: ToolContext,
        on server: MCPServer, servedBy scripted: ScriptedServer
    ) async throws -> CallTool.Result {
        let askedCall = try await whileHolding(held, under: holding, on: server) {
            try await EventRace.start(
                { try await callTool(tool, on: server, under: asking) },
                awaiting: { _ = await scripted.waitForElicitationResults(count: oneElicitationResult) })
        }
        return try await askedCall.value
    }

    // MARK: - Two calls in flight

    @Test(
        "a question that echoes the progress token of its call reaches the run of that call, not the other run",
        arguments: transports)
    func theProgressTokenLinksTheQuestionToItsCall(kind: MCPTransportKind) async throws {
        let (scripted, server, held) = try await Self.connectedForTwoCalls(over: kind)
        try await MCPTestSupport.withConnection(of: server) {
            let (holding, asking) = Self.twoRunsOfOneSession()

            let result = try await Self.call(
                Self.tokenEchoToolName, under: asking.context, whileHolding: held, under: holding.context,
                on: server, servedBy: scripted)

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
        try await MCPTestSupport.withConnection(of: server) {
            let (holding, _) = Self.twoRunsOfOneSession()

            let result = try await Self.call(
                ScriptedServer.elicitEchoToolName, under: holding.context, whileHolding: held, under: holding.context,
                on: server, servedBy: scripted)

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
        try await MCPTestSupport.withConnection(of: server) {
            let (holding, asking) = Self.twoRunsOfOneSession()

            let result = try await Self.call(
                ScriptedServer.elicitEchoToolName, under: asking.context, whileHolding: held, under: holding.context,
                on: server, servedBy: scripted)

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
        try await MCPTestSupport.withConnection(of: server) {
            let (holding, _) = Self.twoRunsOfOneSession()

            let result = try await Self.call(
                Self.unknownTokenToolName, under: holding.context, whileHolding: held, under: holding.context,
                on: server, servedBy: scripted)

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
        try await MCPTestSupport.withConnection(of: server) {
            let registry = try await MultiTool.Builder().withMCP(servers: [server]).buildRegistry()
            let multiTool = MultiTool(registry: registry)
            let (snippetRun, _) = Self.twoRunsOfOneSession()
            let context = snippetRun.context

            // The wait ends on the first of two events: the snippet ends, or
            // the scripted server got the answer to the question. Then the
            // test releases the held call, also when the wait throws. Thus a
            // snippet that does not reach its own release does not keep the
            // held call open, and a second release changes nothing.
            let snippet = try await ensuring({ await held.release() }) {
                try await EventRace.start(
                    {
                        try await ToolContext.$current.withValue(context) {
                            try await multiTool.call(arguments: RunCodeArguments(code: Self.heldAndElicitingSnippet))
                        }
                    },
                    awaiting: { _ = await scripted.waitForElicitationResults(count: Self.oneElicitationResult) })
            }
            let output = await snippet.result

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
        try await MCPTestSupport.withConnection(of: server) {
            try await BoundRun.with { run in
                let (call, request) = try await Self.startElicitingCall(
                    ScriptedServer.elicitEchoToolName, on: server, in: run)
                await run.session.respond(
                    elicitationId: request.elicitationId.description, response: refusal.response)
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
        }
        withExtendedLifetime(scripted) {}
    }

    // MARK: - A headless session

    @Test("under a headless context, elicitEcho gets cancel with the no-user-present reason in _meta")
    func aHeadlessContextCancelsWithTheReason() async throws {
        let (scripted, server) = try await Self.connected(over: .inMemory)
        try await MCPTestSupport.withConnection(of: server) {
            let result = try await Self.callTool(
                ScriptedServer.elicitEchoToolName, on: server, under: Self.headlessContext())

            #expect(Self.rendered(result).contains(Self.cancelText))
            let received = await scripted.receivedElicitationResults.last
            #expect(received?.action == .cancel)
            #expect(Self.reason(of: received) == .string(RunPlane.noUserPresentReason))
        }
        withExtendedLifetime(scripted) {}
    }

    @Test("a headless server cancels a bare elicitEcho with the reason, and never calls the handler")
    func aHeadlessServerCancelsWithoutTheHandler() async throws {
        let probe = HandlerProbe(responding: Self.scriptedAccept)
        let (scripted, server) = try await Self.connected(
            over: .inMemory, elicitationHandler: probe.handler, userPresence: .headless)
        try await MCPTestSupport.withConnection(of: server) {
            let tool = try await Self.tool(named: ScriptedServer.elicitEchoToolName, on: server)

            let output = try await Self.bareCall(tool)

            #expect(output.contains(Self.cancelText))
            let received = await scripted.receivedElicitationResults.last
            #expect(received?.action == .cancel)
            #expect(Self.reason(of: received) == .string(RunPlane.noUserPresentReason))
            #expect(await probe.requests.count == Self.noHandlerCalls)
        }
        withExtendedLifetime(scripted) {}
    }

    @Test("two elicitEcho calls in flight on a headless server each get cancel with the reason")
    func twoCallsOnAHeadlessServerEachCancelWithTheReason() async throws {
        let probe = HandlerProbe(responding: Self.scriptedAccept)
        let (scripted, server) = try await Self.connected(
            over: .inMemory, elicitationHandler: probe.handler, userPresence: .headless)
        try await MCPTestSupport.withConnection(of: server) {
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
        }
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
        try await MCPTestSupport.withConnection(of: server) {
            try await BoundRun.with { run in
                let result = try await Self.callTool(Self.nestedToolName, on: server, under: run.context)

                #expect(Self.rendered(result).contains(Self.declineText))
                #expect(await recordedOperationEvents(of: run.stub).isEmpty)
            }
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
        try await MCPTestSupport.withConnection(of: server) {
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
        let (scripted, server) = try await Self.connected(askingFor: Self.invalidURL)
        try await MCPTestSupport.withConnection(of: server) {
            _ = try await server.call(name: Self.invalidURLToolName, arguments: nil)

            let received = await scripted.receivedElicitationResults.last
            #expect(received?.action == .decline)
            #expect(Self.reason(of: received) == .string(Self.invalidURLReason))
        }
        withExtendedLifetime(scripted) {}
    }

    /// A fresh scripted server that serves ``invalidURLToolName`` with `url`,
    /// beside a server named ``serverName`` connected against it in memory.
    ///
    /// - Parameters:
    ///   - url: The `url` of the URL-mode request of the tool.
    ///   - elicitationHandler: The host's answerer, or `nil`.
    /// - Returns: The scripted server, which the test keeps alive, and the
    ///   connected server.
    /// - Throws: What the connect throws.
    private static func connected(
        askingFor url: String, elicitationHandler: MCPServer.ElicitationHandler? = nil
    ) async throws -> (scripted: ScriptedServer, server: MCPServer) {
        let scripted = ScriptedServer()
        await scripted.addURLElicitingTool(
            named: invalidURLToolName, message: ScriptedServer.elicitURLMessage, url: url,
            elicitationId: ScriptedServer.elicitURLElicitationId)
        let server = try await MCPTestSupport.connectedMCPServer(
            to: scripted, over: .inMemory, name: serverName, elicitationHandler: elicitationHandler)
        return (scripted, server)
    }

    /// Whether the run got the question of `call` before `call` ended.
    ///
    /// The order is fixed, and each wait ends on each result: one child task
    /// waits for the end of `call`, and one child task waits for the
    /// elicitation event of the run. When the run gets the question first,
    /// the session declines it, thus `call` ends also then. When `call` ends
    /// first, the cancel of the group ends the wait for the event.
    ///
    /// - Parameters:
    ///   - call: The call that the server can answer with a question.
    ///   - run: The run that `call` is bound to.
    /// - Returns: `true` when the run got the question, `false` when `call`
    ///   ended with no question to the run.
    /// - Throws: What a child task throws.
    private static func runGotTheQuestion(
        of call: Task<CallTool.Result, any Error>, on run: BoundRun
    ) async throws -> Bool {
        try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask {
                _ = await call.result
                return false
            }
            group.addTask {
                await run.stub.recorder.waitUntil { events in events.contains { $0.kind == .elicitation } }
            }
            let gotTheQuestion = try await group.next() == true
            if gotTheQuestion {
                await declineTheQuestion(of: run, orCancel: call)
            }
            group.cancelAll()
            try await group.waitForAll()
            return gotTheQuestion
        }
    }

    /// Declines the question that the run recorded, thus the call that asked
    /// it ends. When the event of the run holds no request, the test cancels
    /// `call` in its place.
    ///
    /// - Parameters:
    ///   - run: The run that recorded the elicitation event.
    ///   - call: The call that asked the question.
    private static func declineTheQuestion(of run: BoundRun, orCancel call: Task<CallTool.Result, any Error>) async {
        let request = await recordedOperationEvents(of: run.stub, ofKind: .elicitation).first?.elicitation
        if let request {
            await run.session.respond(elicitationId: request.elicitationId.description, response: .decline)
        } else {
            call.cancel()
        }
    }

    /// A `url` that is not an absolute `http` or `https` URL with a host
    /// gets a decline with the reason, and the handler gets no request.
    /// Before the fix, only `URL(string:)` checked the url, thus each such
    /// url went on to the handler.
    @Test("a URL-mode url that is not an absolute http or https URL is declined before the handler", arguments: notHTTPURLs)
    func aNotHTTPURLIsDeclinedBeforeTheHandler(url: String) async throws {
        let probe = HandlerProbe(responding: .decline)
        let (scripted, server) = try await Self.connected(askingFor: url, elicitationHandler: probe.handler)
        try await MCPTestSupport.withConnection(of: server) {
            let tool = try await Self.tool(named: Self.invalidURLToolName, on: server)
            _ = try await Self.bareCall(tool)

            let received = await scripted.receivedElicitationResults.last
            #expect(received?.action == .decline)
            #expect(Self.reason(of: received) == .string(Self.invalidURLReason))
            #expect(await probe.requests.count == Self.noHandlerCalls)
        }
        withExtendedLifetime(scripted) {}
    }

    /// A `url` that is not an absolute `http` or `https` URL with a host
    /// gets a decline with the reason, and the bound run gets no question.
    /// Before the fix, each such url went on to the run.
    @Test("a URL-mode url that is not an absolute http or https URL is declined before the run", arguments: notHTTPURLs)
    func aNotHTTPURLIsDeclinedBeforeTheRun(url: String) async throws {
        let (scripted, server) = try await Self.connected(askingFor: url)
        try await MCPTestSupport.withConnection(of: server) {
            try await BoundRun.with { run in
                let context = run.context
                let call = Task { try await Self.callTool(Self.invalidURLToolName, on: server, under: context) }
                let gotTheQuestion = try await Self.runGotTheQuestion(of: call, on: run)
                _ = try await call.value

                #expect(!gotTheQuestion, "the run got the question of the url \(url)")
                let received = await scripted.receivedElicitationResults.last
                #expect(received?.action == .decline)
                #expect(Self.reason(of: received) == .string(Self.invalidURLReason))
            }
        }
        withExtendedLifetime(scripted) {}
    }

    /// An absolute `https` URL with a host goes on to the handler as before,
    /// also when its scheme is uppercase.
    @Test("a URL-mode url that is an absolute https URL goes on to the handler", arguments: httpURLs)
    func anHTTPURLGoesOnToTheHandler(url: String) async throws {
        let probe = HandlerProbe(responding: .decline)
        let (scripted, server) = try await Self.connected(askingFor: url, elicitationHandler: probe.handler)
        try await MCPTestSupport.withConnection(of: server) {
            let tool = try await Self.tool(named: Self.invalidURLToolName, on: server)
            _ = try await Self.bareCall(tool)

            let requests = await probe.requests
            #expect(requests.count == Self.oneHandlerCall)
            #expect(requests.first?.url?.absoluteString == url)
            #expect(await scripted.receivedElicitationResults.last?.action == .decline)
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
            await server.registerElicitationHandler(on: client, generation: server.connectGeneration)
            released = server
        }
        try #require(released == nil, "the MCPServer stayed alive after its last reference went away")
        let transport = try await scripted.startOnInMemoryPair()
        try await MCPTestSupport.withConnection(of: client) {
            _ = try await client.connect(transport: transport)
            _ = try await client.callTool(name: ScriptedServer.elicitEchoToolName)
        }

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
        try await MCPTestSupport.withConnection(of: server) {
            await server.complete(elicitationId: Self.unknownElicitationId)
            try await scripted.sendElicitationComplete(elicitationId: Self.unknownElicitationId)
            let echoed = try await server.call(
                name: ScriptedServer.echoToolName,
                arguments: [ScriptedServer.echoTextArgument: .string(Self.echoText)])

            #expect(Self.rendered(echoed).contains(Self.echoText))
            #expect(await server.pendingHostElicitationIds.isEmpty)
        }
        withExtendedLifetime(scripted) {}
    }
}
