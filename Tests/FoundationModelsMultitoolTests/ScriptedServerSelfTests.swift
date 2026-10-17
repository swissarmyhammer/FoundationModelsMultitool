import MCP
import MCPTestServer
import Testing

import struct Foundation.Data

@testable import MultitoolTestSupport

/// Self-tests that prove the scripting of `ScriptedServer` works — one test
/// per scenario, each driving the scenario from a plain `MCP.Client`
/// connected over an in-memory transport pair.
///
/// A port of
/// `../FoundationModelsMCP/Tests/FoundationModelsMCPTests/ScriptedServerSelfTests.swift`.
/// The three detach round-trip cases of the source are not here: they drive
/// `GetResultTool`, `CancelCallTool` and `ListCallsTool` over an
/// `MCPServer`, and none of the four is in this package yet. The
/// `poll(timeout:until:)` helper of the source is not here either. No test
/// depends on time: each test waits on an event (a `TestGate`, a
/// `TestCountdown`, or a wait of the scripted server).
///
/// Each test that connects a client gives its body to
/// ``MCPTestSupport/withConnection(of:_:)``. Thus the client disconnects
/// also when the body throws.
@Suite("ScriptedServerSelf")
struct ScriptedServerSelfTests {
    /// The client name every test of this suite connects under.
    private static let clientName = "ScriptedServerSelfTestClient"

    /// The page size of the pagination test.
    private static let paginationPageSize = 2

    /// How many tools the pagination test registers.
    private static let paginationToolCount = 5

    /// How many pages `paginationToolCount` tools make at
    /// `paginationPageSize` per page: two full pages and one of one tool.
    private static let paginationExpectedPageCount = 3

    /// How many `tools/list_changed` notifications the burst test sends.
    private static let burstCount = 7

    /// How many connect attempts the flaky-transport test scripts to fail.
    private static let failingConnectAttempts = 2

    /// The answer the elicitation test scripts the client to give.
    private static let scriptedAnswer = "42"

    /// How many steps the progress-cadence test registers.
    private static let progressSteps = 4

    /// The name of the tool the cancellation test holds in flight.
    private static let heldToolName = "held"

    /// The reason the cancellation test sends.
    private static let cancellationReason = "self-test cancel"

    /// How many steps the slow-build success test registers.
    private static let slowBuildSuccessSteps = 3

    /// How many steps the slow-build failure test registers.
    private static let slowBuildFailureSteps = 2

    /// Records every `notifications/progress` payload a client observes, in
    /// receipt order.
    ///
    /// The notification delivery of the server and the message loop of the
    /// client run on separate tasks. Thus a test waits on ``allArrived``,
    /// which the expected count of records opens, and not on a poll.
    private actor ProgressRecorder {
        /// The recorded payloads.
        private(set) var updates: [ProgressNotification.Parameters] = []

        /// The countdown that the expected number of records opens.
        nonisolated let allArrived: TestCountdown

        /// Makes a recorder that expects `expected` payloads.
        ///
        /// - Parameter expected: How many records open ``allArrived``.
        init(expected: Int) {
            allArrived = TestCountdown(count: expected)
        }

        /// Appends one payload, and records one arrival on ``allArrived``.
        ///
        /// - Parameter update: The payload to record.
        func record(_ update: ProgressNotification.Parameters) {
            updates.append(update)
            allArrived.arrive()
        }
    }

    /// A counter of client-observed notifications.
    ///
    /// The notification delivery of the server and the message loop of the
    /// client run on separate tasks. Thus a test waits on ``allObserved``,
    /// which the expected count of notifications opens, and not on a poll or
    /// a fixed sleep.
    private actor NotificationCounter {
        /// How many notifications were observed.
        private(set) var count = 0

        /// The countdown that the expected number of notifications opens.
        nonisolated let allObserved: TestCountdown

        /// Makes a counter that expects `expected` notifications.
        ///
        /// - Parameter expected: How many notifications open
        ///   ``allObserved``.
        init(expected: Int) {
            allObserved = TestCountdown(count: expected)
        }

        /// Counts one notification, and records one arrival on
        /// ``allObserved``.
        func increment() {
            count += 1
            allObserved.arrive()
        }
    }

    /// A server-side transport that opens ``dropped`` when its
    /// `disconnect()` ends.
    ///
    /// The transport-drop test waits on ``dropped`` to know that the tool
    /// dropped the transport. Before, the test slept for a fixed time.
    private actor DisconnectSignalingTransport: WrappingTransport {
        /// The transport every operation delegates to.
        let wrapped: any Transport

        /// The receive stream of ``wrapped``, cached by the connect.
        var wrappedReceiveStream: AsyncThrowingStream<Data, Swift.Error>?

        /// The gate that opens when the disconnect of ``wrapped`` ends.
        nonisolated let dropped = TestGate()

        /// The logger of this double — a no-op.
        nonisolated let logger = DisconnectSignalingTransport.noOpLogger(
            label: "mcp.transport.disconnect-signaling")

        /// Makes a wrapper around `wrapped`.
        ///
        /// - Parameter wrapped: The transport to delegate to.
        init(wrapping wrapped: any Transport) {
            self.wrapped = wrapped
        }

        /// Delegates the connect to the wrapped transport.
        ///
        /// - Throws: What the `connect()` of the wrapped transport throws.
        func connect() async throws {
            try await connectWrapped()
        }

        /// Delegates the disconnect to the wrapped transport, and then opens
        /// ``dropped``.
        func disconnect() async {
            await wrapped.disconnect()
            dropped.open()
        }
    }

    /// Connects a fresh client to `scripted` over an in-memory pair.
    ///
    /// - Parameters:
    ///   - scripted: The server to connect to.
    ///   - capabilities: The client capabilities to advertise.
    /// - Returns: The connected client.
    /// - Throws: What the connect throws.
    private func connect(
        to scripted: ScriptedServer, advertising capabilities: Client.Capabilities = .init()
    ) async throws -> Client {
        try await MCPTestSupport.connectedServer(
            to: scripted, over: .inMemory, clientName: Self.clientName, capabilities: capabilities)
    }

    /// Connects a client to `scripted` and records every progress
    /// notification it observes.
    ///
    /// - Parameters:
    ///   - scripted: The server to connect to.
    ///   - expected: How many progress notifications open the
    ///     `allArrived` countdown of the recorder.
    /// - Returns: The connected client and its recorder.
    /// - Throws: What the connect throws.
    private func connectRecordingProgress(
        to scripted: ScriptedServer, expecting expected: Int
    ) async throws -> (client: Client, recorder: ProgressRecorder) {
        let client = try await connect(to: scripted)
        let recorder = ProgressRecorder(expected: expected)
        await client.onNotification(ProgressNotification.self) { message in
            await recorder.record(message.params)
        }
        return (client, recorder)
    }

    /// The progress values `steps` notifications carry: `1` through `steps`.
    ///
    /// - Parameter steps: The step count.
    /// - Returns: The expected `progress` sequence.
    private static func expectedProgress(steps: Int) -> [Double] {
        (1...steps).map(Double.init)
    }

    // MARK: - tools/list pagination

    @Test("tools/list pagination returns exactly the expected number of pages")
    func toolsListPaginationPageCount() async throws {
        let scripted = ScriptedServer(toolsPageSize: Self.paginationPageSize)
        for index in 0..<Self.paginationToolCount {
            await scripted.addTool(ScriptedServer.echoTool(named: "tool-\(index)"))
        }
        let client = try await connect(to: scripted)
        try await MCPTestSupport.withConnection(of: client) {
            var collectedNames: [String] = []
            var cursor: String?
            var pageCount = 0
            repeat {
                let page = try await client.listTools(cursor: cursor)
                collectedNames.append(contentsOf: page.tools.map(\.name))
                cursor = page.nextCursor
                pageCount += 1
            } while cursor != nil

            #expect(pageCount == Self.paginationExpectedPageCount)
            #expect(collectedNames.count == Self.paginationToolCount)
        }
    }

    // MARK: - tools/list_changed bursts

    @Test("emitToolListChangedBurst sends exactly the scripted number of notifications")
    func toolListChangedBurstEmission() async throws {
        let scripted = ScriptedServer()
        let client = try await connect(to: scripted)
        try await MCPTestSupport.withConnection(of: client) {
            let counter = NotificationCounter(expected: Self.burstCount)
            await client.onNotification(ToolListChangedNotification.self) { _ in
                await counter.increment()
            }

            try await scripted.emitToolListChangedBurst(count: Self.burstCount)

            try await counter.allObserved.wait()
            #expect(await counter.count == Self.burstCount)
        }
    }

    // MARK: - add/remove/re-schema on command or on a scheduled trigger

    @Test("tools can be added, removed, re-schema'd on command, and added on a scheduled trigger")
    func toolMutationOnCommandAndTimer() async throws {
        let scripted = ScriptedServer()
        await scripted.addTool(ScriptedServer.echoTool(named: "alpha"))
        let client = try await connect(to: scripted)
        try await MCPTestSupport.withConnection(of: client) {
            var page = try await client.listTools()
            #expect(page.tools.map(\.name) == ["alpha"])

            await scripted.addTool(ScriptedServer.echoTool(named: "beta"))
            page = try await client.listTools()
            #expect(Set(page.tools.map(\.name)) == ["alpha", "beta"])

            await scripted.removeTool(named: "alpha")
            page = try await client.listTools()
            #expect(page.tools.map(\.name) == ["beta"])

            let reschemaed = MCP.Tool(
                name: "beta",
                description: "updated description",
                inputSchema: JSONSchemaBuilder.emptySchema
            )
            await scripted.replaceTool(
                ScriptedTool(definition: reschemaed) { _ in
                    CallTool.Result(content: [.text(text: "beta", annotations: nil, _meta: nil)])
                }
            )
            page = try await client.listTools()
            #expect(page.tools.first?.description == "updated description")

            // The scheduled mutation runs when the test opens `trigger`, and it
            // opens `applied` when it is done. No time sets when it runs.
            let trigger = TestGate()
            let applied = TestGate()
            await scripted.scheduleMutation(after: { try? await trigger.wait() }) { server in
                await server.addTool(ScriptedServer.echoTool(named: "gamma"))
                applied.open()
            }
            trigger.open()
            try await applied.wait()
            page = try await client.listTools()
            #expect(page.tools.map(\.name).contains("gamma"))
        }
    }

    // MARK: - The dynamic toolset scenario, one stage on each command

    @Test("the dynamic scenario runs one stage on each advance, then reports that no stage is left")
    func dynamicScenarioRunsOneStageOnEachAdvance() async throws {
        let counter = ScriptedServer.dynamicToolsetReschemadToolName
        let greeter = ScriptedServer.dynamicToolsetVanishingToolName
        let scripted = ScriptedServer()
        await scripted.startDynamicToolsetScenario()
        let client = try await connect(to: scripted)
        try await MCPTestSupport.withConnection(of: client) {
            // No stage runs before the first command.
            var page = try await client.listTools()
            #expect(page.tools.map(\.name) == [counter])

            #expect(await scripted.advanceDynamicToolsetScenario())
            page = try await client.listTools()
            #expect(page.tools.map(\.name) == [counter, greeter])

            #expect(await scripted.advanceDynamicToolsetScenario())
            page = try await client.listTools()
            #expect(page.tools.map(\.name) == [counter, greeter])
            #expect(page.tools.first?.inputSchema != JSONSchemaBuilder.emptySchema)

            #expect(await scripted.advanceDynamicToolsetScenario())
            page = try await client.listTools()
            #expect(page.tools.map(\.name) == [counter])

            #expect(await scripted.advanceDynamicToolsetScenario() == false)
        }
    }

    // MARK: - fail-N-times-then-succeed connects

    @Test("FlakyConnectTransport fails the scripted number of connect attempts, then succeeds")
    func connectFailureCountdown() async throws {
        let (clientTransport, _) = await InMemoryTransport.createConnectedPair()
        let flaky = FlakyConnectTransport(
            wrapping: clientTransport, failingConnectAttempts: Self.failingConnectAttempts)
        try await ensuring({ await flaky.disconnect() }) {
            for _ in 0..<Self.failingConnectAttempts {
                await #expect(throws: MCPError.self) {
                    try await flaky.connect()
                }
            }
            try await flaky.connect()

            let attempts = await flaky.connectAttempts
            #expect(attempts == Self.failingConnectAttempts + 1)
        }
    }

    // MARK: - transport drop mid-call

    @Test("dropping the transport mid-call leaves the in-flight call unanswered")
    func transportDropMidCall() async throws {
        let scripted = ScriptedServer()
        await scripted.addTransportDroppingTool(named: "drop")
        // The server end is wrapped, so the test knows when the tool dropped
        // it. The rest is what `connect(to:)` does over an in-memory pair.
        let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()
        let signaling = DisconnectSignalingTransport(wrapping: serverTransport)
        try await scripted.start(transport: signaling)
        let client = MCPTestSupport.makeClient(name: Self.clientName)
        _ = try await client.connect(transport: clientTransport)
        try await MCPTestSupport.withConnection(of: client) {
            let callTask = Task {
                try await client.callTool(name: "drop")
            }

            // Wait until the call reached the server and the tool dropped the
            // transport.
            try await signaling.dropped.wait()

            // A disconnect resolves every request still pending with a
            // "Client disconnected" error. Had the drop not stopped the answer,
            // `callTask` would already hold a result and this would fail.
            await client.disconnect()

            await #expect(throws: (any Error).self) {
                _ = try await callTask.value
            }
        }
    }

    // MARK: - elicit mid-call

    @Test("a tool that elicits mid-call round-trips the client's scripted response")
    func elicitRoundTrip() async throws {
        let scripted = ScriptedServer()
        await scripted.addLoopbackTools()
        let client = try await connect(
            to: scripted, advertising: Client.Capabilities(elicitation: .init()))
        try await MCPTestSupport.withConnection(of: client) {
            await client.withElicitationHandler { params in
                guard case .form(let formParams) = params else {
                    return CreateElicitation.Result(action: .decline)
                }
                #expect(formParams.message == ScriptedServer.elicitEchoMessage)
                return CreateElicitation.Result(
                    action: .accept, content: [ScriptedServer.elicitEchoAnswerField: .string(Self.scriptedAnswer)])
            }

            let context = try await client.send(CallTool.request(.init(name: ScriptedServer.elicitEchoToolName)))
            let result = try await context.value

            #expect(result.content.contains { content in
                if case .text(let text, _, _) = content {
                    return text.contains("accept")
                }
                return false
            })
            #expect(
                result.structuredContent?.objectValue?[ScriptedServer.elicitEchoAnswerField]?.stringValue
                    == Self.scriptedAnswer)
        }
    }

    @Test("the URL-mode loopback tool sends a URL elicitation, and the complete notification names its id")
    func urlElicitRoundTrip() async throws {
        let scripted = ScriptedServer()
        await scripted.addLoopbackTools()
        let client = try await connect(
            to: scripted, advertising: Client.Capabilities(elicitation: .init()))
        try await MCPTestSupport.withConnection(of: client) {
            await client.withElicitationHandler { params in
                guard case .url(let urlParams) = params else {
                    return CreateElicitation.Result(action: .decline)
                }
                #expect(urlParams.url == ScriptedServer.elicitURLLink)
                #expect(urlParams.elicitationId == ScriptedServer.elicitURLElicitationId)
                return CreateElicitation.Result(action: .accept)
            }
            let counter = NotificationCounter(expected: 1)
            await client.onNotification(ElicitationCompleteNotification.self) { message in
                #expect(message.params.elicitationId == ScriptedServer.elicitURLElicitationId)
                await counter.increment()
            }

            let result = try await client.callTool(name: ScriptedServer.elicitURLToolName)
            #expect(result.isError != true)
            try await scripted.sendElicitationComplete(elicitationId: ScriptedServer.elicitURLElicitationId)

            try await counter.allObserved.wait()
            #expect(await counter.count == 1)
        }
    }

    // MARK: - periodic progress notifications

    @Test("a long call reports progress at the scripted cadence")
    func progressCadence() async throws {
        let scripted = ScriptedServer()
        await scripted.addProgressReportingTool(named: "slow", totalSteps: Self.progressSteps)
        let (client, recorder) = try await connectRecordingProgress(
            to: scripted, expecting: Self.progressSteps)
        try await MCPTestSupport.withConnection(of: client) {
            let meta = Metadata(progressToken: .string("progress-token"))
            _ = try await client.callTool(name: "slow", arguments: nil, meta: meta)

            // The response of the tool proves only that the server sent the last
            // notification, not that the client's message loop processed it.
            try await recorder.allArrived.wait()

            let updates = await recorder.updates
            #expect(updates.count == Self.progressSteps)
            #expect(updates.map(\.progress) == Self.expectedProgress(steps: Self.progressSteps))
            #expect(updates.allSatisfy { $0.total == Double(Self.progressSteps) })
        }
    }

    // MARK: - recording inbound notifications (cancelled)

    /// The call holds on the server until the test releases it, thus the
    /// cancel always goes out while the call is in flight.
    @Test("a cancelled notification is recorded for test assertion")
    func cancelledNotificationRecording() async throws {
        let scripted = ScriptedServer()
        let held = HeldScriptedTool(named: Self.heldToolName)
        await scripted.addTool(held.scriptedTool)
        let client = try await connect(to: scripted)
        try await MCPTestSupport.withConnection(of: client) {
            let context = try await client.send(CallTool.request(.init(name: Self.heldToolName)))
            try await held.waitForArrival()
            try await client.cancelRequest(context.requestID, reason: Self.cancellationReason)

            let recorded = await scripted.waitForRecordedNotifications(count: 1)
            #expect(recorded.count == 1)
            #expect(recorded.first?.method == CancelledNotification.name)
            #expect(recorded.first?.reason == Self.cancellationReason)
            await held.release()
        }
    }

    // MARK: - slow build

    @Test("the slow-build tool reports progress naming its current phase, and succeeds by default")
    func slowBuildToolReportsProgressAndSucceeds() async throws {
        let scripted = ScriptedServer()
        await scripted.addSlowBuildTool(totalSteps: Self.slowBuildSuccessSteps)
        let (client, recorder) = try await connectRecordingProgress(
            to: scripted, expecting: Self.slowBuildSuccessSteps)
        try await MCPTestSupport.withConnection(of: client) {
            let meta = Metadata(progressToken: .string("slow-build-token"))
            let result = try await client.callTool(name: ServerMode.slowBuildToolName, arguments: nil, meta: meta)

            try await recorder.allArrived.wait()

            let updates = await recorder.updates
            #expect(updates.count == Self.slowBuildSuccessSteps)
            #expect(updates.map(\.progress) == Self.expectedProgress(steps: Self.slowBuildSuccessSteps))
            #expect(updates.allSatisfy { $0.total == Double(Self.slowBuildSuccessSteps) })
            #expect(updates.allSatisfy { ($0.message ?? "").contains("step") })
            #expect(result.isError != true)
        }
    }

    @Test("the slow-build tool finishes as isError when told should_fail, with no reliance on wall-clock timing")
    func slowBuildToolHonorsShouldFailControl() async throws {
        let scripted = ScriptedServer()
        await scripted.addSlowBuildTool(totalSteps: Self.slowBuildFailureSteps)
        let client = try await connect(to: scripted)
        try await MCPTestSupport.withConnection(of: client) {
            let result = try await client.callTool(
                name: ServerMode.slowBuildToolName, arguments: ["should_fail": .bool(true)])

            #expect(result.isError == true)
        }
    }
}
