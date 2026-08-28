import Foundation
import MCP
import MCPTestServer
import Testing

/// Tests of the in-process HTTP loopback: a bare `MCP.Client` over
/// `HTTPClientTransport(endpoint:configuration:)` against a `ScriptedServer`
/// served through `LoopbackHTTPServer`, in one process, with no socket.
///
/// The three loopback tools (`echo`, `elicitEcho`, `elicitURL`), the
/// `tools/list_changed` notification and a client that asks to resume a stream
/// are the cases. The resume case runs over each spelling of the resume header
/// name, and the last test runs one case over both transports of
/// ``MCPTransportKind``.
///
/// The suite is `.serialized` so its tests run one at a time. Each test holds a
/// live SSE stream and a registry entry of `LoopbackHTTPServer` open for its
/// whole body, and that registry is process-wide, so one test at a time keeps
/// each of them owned by exactly one test. This is a platform-native
/// serialization trait, not an environment switch, and every test still runs on
/// every `swift test`.
///
/// The trait is not what makes a server-to-client message arrive. An earlier
/// note here said several open streams loaded the shared cooperative thread
/// pool past a threshold; that was measured wrong. The message was dropped, and
/// not delayed — see the header of `LoopbackHTTPServer.swift`.
@Suite("LoopbackHTTPServer", .serialized)
struct LoopbackHTTPServerTests {
    /// The client name every test of this suite connects under.
    private static let clientName = "LoopbackHTTPServerTestClient"

    /// The text the echo test sends and expects back.
    private static let echoText = "over the loopback"

    /// The answer the elicitation test scripts the client to give.
    private static let scriptedAnswer = "42"

    /// The client capabilities the card names: form and URL elicitation.
    private static let elicitingCapabilities = Client.Capabilities(
        elicitation: Client.Capabilities.Elicitation(form: .init(), url: .init()))

    /// The header a client sends to ask a server to resume a stream.
    private static let lastEventIDHeader = "Last-Event-ID"

    /// The cases the resume test spells ``lastEventIDHeader`` in: the usual
    /// one, and the same name in lower case.
    ///
    /// A header name has no case in HTTP, and the loopback compares this one
    /// without case, so each spelling must reach the same standalone SSE
    /// stream. The lower-case form is not an unusual client: HTTP/2 and HTTP/3
    /// send every header name that way. The second spelling is derived from the
    /// first one, so the two can never name different headers.
    private static let resumeHeaderSpellings = [
        lastEventIDHeader, lastEventIDHeader.lowercased(),
    ]

    /// The HTTP method of the standalone SSE stream request.
    private static let eventStreamMethod = "GET"

    /// The `Last-Event-ID` the resume case sends — an id of no stream of the
    /// session, so a loopback that read the header would answer 400 and open
    /// no standalone stream at all.
    private static let idOfNoStream = "an-event-of-no-stream"

    /// A counter of client-observed notifications, awaited through
    /// `TestPoll`: the SSE delivery of the server and the message loop of
    /// the client run on separate tasks.
    private actor NotificationCounter {
        /// How many notifications were observed.
        private(set) var count = 0

        /// Counts one notification.
        func increment() {
            count += 1
        }
    }

    /// A started loopback with a client connected over it.
    private struct Connection {
        /// The loopback server, to stop at the end of the test.
        let loopback: LoopbackHTTPServer

        /// The connected client.
        let client: Client

        /// Disconnects the client, then stops the loopback.
        func close() async {
            await client.disconnect()
            await loopback.stop()
        }
    }

    /// Starts `scripted` behind a loopback and connects a fresh client over
    /// `HTTPClientTransport(endpoint:configuration:)`, then waits until the
    /// standalone SSE stream of the client is open, so a server-initiated
    /// message has a stream to go to.
    ///
    /// A started loopback holds the one process-wide gate of
    /// `LoopbackHTTPServer` until its `stop()`, so a connect that throws after
    /// the start stops the loopback before it rethrows. A loopback nobody stops
    /// parks every later `.http` test of the process for ever, which reports as
    /// a hang of the whole run and not as the one failure that caused it.
    ///
    /// - Parameters:
    ///   - scripted: The server to serve.
    ///   - capabilities: The client capabilities to advertise.
    ///   - lastEventID: What every `GET` of the client carries as
    ///     `Last-Event-ID`, or `nil` for a client that asks to resume nothing.
    ///   - headerName: The case the client spells that header name in. The
    ///     usual spelling by default — see ``resumeHeaderSpellings``.
    /// - Returns: The loopback and the connected client.
    /// - Throws: What the start, the connect, or the wait throws.
    private func connect(
        to scripted: ScriptedServer,
        advertising capabilities: Client.Capabilities = .init(),
        resumingFrom lastEventID: String? = nil,
        sendingResumeHeaderNamed headerName: String = LoopbackHTTPServerTests.lastEventIDHeader
    ) async throws -> Connection {
        let loopback = LoopbackHTTPServer(serving: scripted)
        let (endpoint, configuration) = try await loopback.start()
        do {
            let client = MCPTestSupport.makeClient(name: Self.clientName, capabilities: capabilities)
            _ = try await client.connect(
                transport: HTTPClientTransport(
                    endpoint: endpoint, configuration: configuration,
                    requestModifier: {
                        Self.addingResumeHeader(to: $0, resumingFrom: lastEventID, named: headerName)
                    }))
            try await TestPoll.waitUntil("the standalone SSE stream") {
                await loopback.isServingEventStream
            }
            return Connection(loopback: loopback, client: client)
        } catch {
            await loopback.stop()
            throw error
        }
    }

    /// `request` with `lastEventID` set under `headerName`, when it is a
    /// standalone SSE stream request and `lastEventID` is not `nil`.
    ///
    /// `URLRequest` keeps the case the caller spells a header name in, and the
    /// loader hands that same spelling to the `URLProtocol`, so `headerName`
    /// reaches the loopback as it is written here.
    ///
    /// - Parameters:
    ///   - request: The request the client is about to send.
    ///   - lastEventID: The id to ask to resume from, or `nil` to ask nothing.
    ///   - headerName: The name to set that id under, in the case to send.
    /// - Returns: The request to send.
    private static func addingResumeHeader(
        to request: URLRequest, resumingFrom lastEventID: String?, named headerName: String
    ) -> URLRequest {
        guard let lastEventID, request.httpMethod == Self.eventStreamMethod else {
            return request
        }
        var carrying = request
        carrying.setValue(lastEventID, forHTTPHeaderField: headerName)
        return carrying
    }

    // MARK: - initialize, tools/list, tools/call

    @Test("a client completes initialize, tools/list and a tools/call of echo over the loopback")
    func initializeListAndCallEcho() async throws {
        let scripted = ScriptedServer()
        await scripted.addLoopbackTools()
        let connection = try await connect(to: scripted)
        defer { Task { await connection.close() } }

        let page = try await connection.client.listTools()
        #expect(page.tools.map(\.name) == ScriptedServer.loopbackToolNames)

        let result = try await connection.client.callTool(
            name: ScriptedServer.echoToolName,
            arguments: [ScriptedServer.echoTextArgument: .string(Self.echoText)])
        #expect(result.content == [.text(text: Self.echoText, annotations: nil, _meta: nil)])
    }

    // MARK: - elicitation/create over the loopback

    @Test("a server-initiated elicitation/create reaches the client, and the answer returns to the tool")
    func elicitEchoRoundTrip() async throws {
        let scripted = ScriptedServer()
        await scripted.addLoopbackTools()
        let connection = try await connect(to: scripted, advertising: Self.elicitingCapabilities)
        defer { Task { await connection.close() } }

        await connection.client.withElicitationHandler { params in
            guard case .form(let formParams) = params else {
                return CreateElicitation.Result(action: .decline)
            }
            #expect(formParams.message == ScriptedServer.elicitEchoMessage)
            return CreateElicitation.Result(
                action: .accept, content: [ScriptedServer.elicitEchoAnswerField: .string(Self.scriptedAnswer)])
        }

        let context = try await connection.client.send(
            CallTool.request(.init(name: ScriptedServer.elicitEchoToolName)))
        let result = try await context.value
        #expect(result.isError != true)
        #expect(
            result.structuredContent?.objectValue?[ScriptedServer.elicitEchoAnswerField]?.stringValue
                == Self.scriptedAnswer)
    }

    // MARK: - tools/list_changed over the SSE stream

    @Test("notifications/tools/list_changed reaches the client over the loopback SSE stream")
    func toolListChangedOverEventStream() async throws {
        let scripted = ScriptedServer()
        await scripted.addLoopbackTools()
        let connection = try await connect(to: scripted)
        defer { Task { await connection.close() } }

        let counter = NotificationCounter()
        await connection.client.onNotification(ToolListChangedNotification.self) { _ in
            await counter.increment()
        }
        try await scripted.emitToolListChanged()

        let observed = await TestPoll.holds { await counter.count == 1 }
        #expect(observed)
    }

    // MARK: - a client that asks to resume a stream

    /// The loopback reads no `Last-Event-ID`, so a `GET` that carries one still
    /// opens the standalone SSE stream and still carries a server-initiated
    /// message. `HTTPClientTransport` of the sdk keeps ONE last event id for
    /// every stream it reads, so the id it sends on a `GET` can be the id of a
    /// `POST` response stream; a loopback that read the header would bind the
    /// standalone stream to that other stream, or answer 400, and every
    /// server-initiated message would then reach nothing. See the header of
    /// `LoopbackHTTPServer.swift`.
    ///
    /// The case of the header name is what each argument moves. The loopback
    /// compares that name without case, and `StatefulHTTPServerTransport`
    /// reads it without case too, so a spelling the loopback let through would
    /// reach the resume path of the sdk exactly as the usual spelling does.
    /// Each spelling of ``resumeHeaderSpellings`` must therefore reach the same
    /// standalone stream.
    @Test(
        "a client that asks to resume a stream still gets the standalone SSE stream",
        arguments: LoopbackHTTPServerTests.resumeHeaderSpellings)
    func aResumeRequestStillGetsTheStandaloneStream(headerName: String) async throws {
        let scripted = ScriptedServer()
        await scripted.addLoopbackTools()
        let connection = try await connect(
            to: scripted, resumingFrom: Self.idOfNoStream, sendingResumeHeaderNamed: headerName)
        defer { Task { await connection.close() } }

        let counter = NotificationCounter()
        await connection.client.onNotification(ToolListChangedNotification.self) { _ in
            await counter.increment()
        }
        try await scripted.emitToolListChanged()

        let observed = await TestPoll.holds { await counter.count == 1 }
        #expect(observed)
    }

    // MARK: - one case over both transports

    @Test("tools/list names the loopback tools over each transport", arguments: [MCPTransportKind.inMemory, .http])
    func toolsListOverEachTransport(kind: MCPTransportKind) async throws {
        let scripted = ScriptedServer()
        await scripted.addLoopbackTools()
        let client = try await MCPTestSupport.connectedServer(
            to: scripted, over: kind, clientName: Self.clientName)
        defer { Task { await client.disconnect() } }

        let page = try await client.listTools()
        #expect(page.tools.map(\.name) == ScriptedServer.loopbackToolNames)
    }
}
