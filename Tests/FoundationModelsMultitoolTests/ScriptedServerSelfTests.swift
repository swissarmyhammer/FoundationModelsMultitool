import MCP
import MCPTestServer
import Testing

/// Self-tests that prove the scripting of `ScriptedServer` works — one test
/// per scenario, each driving the scenario from a plain `MCP.Client`
/// connected over an in-memory transport pair.
///
/// A port of
/// `../FoundationModelsMCP/Tests/FoundationModelsMCPTests/ScriptedServerSelfTests.swift`.
/// The three detach round-trip cases of the source are not here: they drive
/// `GetResultTool`, `CancelCallTool` and `ListCallsTool` over an
/// `MCPServer`, and none of the four is in this package yet. The
/// `poll(timeout:until:)` helper of the source is `TestPoll`, the one poll
/// of this test target.
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

    /// How long the timer test waits before its scheduled mutation.
    private static let timedMutationDelay: Duration = .milliseconds(20)

    /// How many connect attempts the flaky-transport test scripts to fail.
    private static let failingConnectAttempts = 2

    /// How long the transport-drop test gives the call to reach the server
    /// and trigger the drop.
    private static let transportDropSettleDelay: Duration = .milliseconds(150)

    /// The answer the elicitation test scripts the client to give.
    private static let scriptedAnswer = "42"

    /// How many steps the progress-cadence test registers.
    private static let progressSteps = 4

    /// The delay between steps of the progress-cadence test.
    private static let progressStepDelay: Duration = .milliseconds(10)

    /// How many steps the cancellation test registers — enough that the call
    /// is still in flight when the cancel goes out.
    private static let cancellationSteps = 20

    /// The delay between steps of the cancellation test.
    private static let cancellationStepDelay: Duration = .milliseconds(20)

    /// How long the cancellation test lets the call run before it cancels.
    private static let cancellationLeadTime: Duration = .milliseconds(50)

    /// The reason the cancellation test sends.
    private static let cancellationReason = "self-test cancel"

    /// How long a test waits for the server to record a notification.
    private static let recordedNotificationTimeout: Duration = .seconds(2)

    /// How many steps the slow-build success test registers.
    private static let slowBuildSuccessSteps = 3

    /// How many steps the slow-build failure test registers.
    private static let slowBuildFailureSteps = 2

    /// The delay between steps of the slow-build tests.
    private static let slowBuildStepDelay: Duration = .milliseconds(5)

    /// Records every `notifications/progress` payload a client observes, in
    /// receipt order.
    private actor ProgressRecorder {
        /// The recorded payloads.
        private(set) var updates: [ProgressNotification.Parameters] = []

        /// Appends one payload.
        ///
        /// - Parameter update: The payload to record.
        func record(_ update: ProgressNotification.Parameters) {
            updates.append(update)
        }
    }

    /// A counter of client-observed notifications, awaited through
    /// `TestPoll` instead of a fixed sleep: the notification delivery of the
    /// server and the message loop of the client run on separate tasks.
    private actor NotificationCounter {
        /// How many notifications were observed.
        private(set) var count = 0

        /// Counts one notification.
        func increment() {
            count += 1
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
    /// - Parameter scripted: The server to connect to.
    /// - Returns: The connected client and its recorder.
    /// - Throws: What the connect throws.
    private func connectRecordingProgress(
        to scripted: ScriptedServer
    ) async throws -> (client: Client, recorder: ProgressRecorder) {
        let client = try await connect(to: scripted)
        let recorder = ProgressRecorder()
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
        await client.disconnect()
    }

    // MARK: - tools/list_changed bursts

    @Test("emitToolListChangedBurst sends exactly the scripted number of notifications")
    func toolListChangedBurstEmission() async throws {
        let scripted = ScriptedServer()
        let client = try await connect(to: scripted)

        let counter = NotificationCounter()
        await client.onNotification(ToolListChangedNotification.self) { _ in
            await counter.increment()
        }

        try await scripted.emitToolListChangedBurst(count: Self.burstCount)

        let observed = await TestPoll.holds { await counter.count >= Self.burstCount }
        #expect(observed)
        #expect(await counter.count == Self.burstCount)
        await client.disconnect()
    }

    // MARK: - add/remove/re-schema on command or timer

    @Test("tools can be added, removed, re-schema'd on command, and added on a timer")
    func toolMutationOnCommandAndTimer() async throws {
        let scripted = ScriptedServer()
        await scripted.addTool(ScriptedServer.echoTool(named: "alpha"))
        let client = try await connect(to: scripted)

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

        await scripted.scheduleMutation(after: Self.timedMutationDelay) { server in
            await server.addTool(ScriptedServer.echoTool(named: "gamma"))
        }
        let gammaArrived = await TestPoll.holds {
            (try? await client.listTools().tools.map(\.name).contains("gamma")) ?? false
        }
        #expect(gammaArrived)
        await client.disconnect()
    }

    // MARK: - fail-N-times-then-succeed connects

    @Test("FlakyConnectTransport fails the scripted number of connect attempts, then succeeds")
    func connectFailureCountdown() async throws {
        let (clientTransport, _) = await InMemoryTransport.createConnectedPair()
        let flaky = FlakyConnectTransport(
            wrapping: clientTransport, failingConnectAttempts: Self.failingConnectAttempts)

        for _ in 0..<Self.failingConnectAttempts {
            await #expect(throws: MCPError.self) {
                try await flaky.connect()
            }
        }
        try await flaky.connect()

        let attempts = await flaky.connectAttempts
        #expect(attempts == Self.failingConnectAttempts + 1)
        await flaky.disconnect()
    }

    // MARK: - transport drop mid-call

    @Test("dropping the transport mid-call leaves the in-flight call unanswered")
    func transportDropMidCall() async throws {
        let scripted = ScriptedServer()
        await scripted.addTransportDroppingTool(named: "drop")
        let client = try await connect(to: scripted)

        let callTask = Task {
            try await client.callTool(name: "drop")
        }

        // Give the call time to reach the server and trigger the drop.
        try await Task.sleep(for: Self.transportDropSettleDelay)

        // A disconnect resolves every request still pending with a
        // "Client disconnected" error. Had the drop not stopped the answer,
        // `callTask` would already hold a result and this would fail.
        await client.disconnect()

        await #expect(throws: (any Error).self) {
            _ = try await callTask.value
        }
    }

    // MARK: - elicit mid-call

    @Test("a tool that elicits mid-call round-trips the client's scripted response")
    func elicitRoundTrip() async throws {
        let scripted = ScriptedServer()
        await scripted.addLoopbackTools()
        let client = try await connect(
            to: scripted, advertising: Client.Capabilities(elicitation: .init()))

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
        await client.disconnect()
    }

    @Test("the URL-mode loopback tool sends a URL elicitation, and the complete notification names its id")
    func urlElicitRoundTrip() async throws {
        let scripted = ScriptedServer()
        await scripted.addLoopbackTools()
        let client = try await connect(
            to: scripted, advertising: Client.Capabilities(elicitation: .init()))

        await client.withElicitationHandler { params in
            guard case .url(let urlParams) = params else {
                return CreateElicitation.Result(action: .decline)
            }
            #expect(urlParams.url == ScriptedServer.elicitURLLink)
            #expect(urlParams.elicitationId == ScriptedServer.elicitURLElicitationId)
            return CreateElicitation.Result(action: .accept)
        }
        let counter = NotificationCounter()
        await client.onNotification(ElicitationCompleteNotification.self) { message in
            #expect(message.params.elicitationId == ScriptedServer.elicitURLElicitationId)
            await counter.increment()
        }

        let result = try await client.callTool(name: ScriptedServer.elicitURLToolName)
        #expect(result.isError != true)
        try await scripted.sendElicitationComplete(elicitationId: ScriptedServer.elicitURLElicitationId)

        let completed = await TestPoll.holds { await counter.count == 1 }
        #expect(completed)
        await client.disconnect()
    }

    // MARK: - periodic progress notifications

    @Test("a long call reports progress at the scripted cadence")
    func progressCadence() async throws {
        let scripted = ScriptedServer()
        await scripted.addProgressReportingTool(
            named: "slow", totalSteps: Self.progressSteps, stepDelay: Self.progressStepDelay)
        let (client, recorder) = try await connectRecordingProgress(to: scripted)

        let meta = Metadata(progressToken: .string("progress-token"))
        _ = try await client.callTool(name: "slow", arguments: nil, meta: meta)

        // The response of the tool proves only that the server sent the last
        // notification, not that the client's message loop processed it.
        let arrived = await TestPoll.holds { await recorder.updates.count >= Self.progressSteps }
        #expect(arrived)

        let updates = await recorder.updates
        #expect(updates.count == Self.progressSteps)
        #expect(updates.map(\.progress) == Self.expectedProgress(steps: Self.progressSteps))
        #expect(updates.allSatisfy { $0.total == Double(Self.progressSteps) })
        await client.disconnect()
    }

    // MARK: - recording inbound notifications (cancelled)

    @Test("a cancelled notification is recorded for test assertion")
    func cancelledNotificationRecording() async throws {
        let scripted = ScriptedServer()
        await scripted.addProgressReportingTool(
            named: "slow", totalSteps: Self.cancellationSteps, stepDelay: Self.cancellationStepDelay)
        let client = try await connect(to: scripted)

        let context = try await client.send(CallTool.request(.init(name: "slow")))
        try await Task.sleep(for: Self.cancellationLeadTime)
        try await client.cancelRequest(context.requestID, reason: Self.cancellationReason)

        let recorded = await scripted.waitForRecordedNotifications(
            count: 1, timeout: Self.recordedNotificationTimeout)
        #expect(recorded.count == 1)
        #expect(recorded.first?.method == CancelledNotification.name)
        #expect(recorded.first?.reason == Self.cancellationReason)
        await client.disconnect()
    }

    // MARK: - slow build

    @Test("the slow-build tool reports progress naming its current phase, and succeeds by default")
    func slowBuildToolReportsProgressAndSucceeds() async throws {
        let scripted = ScriptedServer()
        await scripted.addSlowBuildTool(totalSteps: Self.slowBuildSuccessSteps, stepDelay: Self.slowBuildStepDelay)
        let (client, recorder) = try await connectRecordingProgress(to: scripted)

        let meta = Metadata(progressToken: .string("slow-build-token"))
        let result = try await client.callTool(name: ServerMode.slowBuildToolName, arguments: nil, meta: meta)

        let arrived = await TestPoll.holds { await recorder.updates.count >= Self.slowBuildSuccessSteps }
        #expect(arrived)

        let updates = await recorder.updates
        #expect(updates.count == Self.slowBuildSuccessSteps)
        #expect(updates.map(\.progress) == Self.expectedProgress(steps: Self.slowBuildSuccessSteps))
        #expect(updates.allSatisfy { $0.total == Double(Self.slowBuildSuccessSteps) })
        #expect(updates.allSatisfy { ($0.message ?? "").contains("step") })
        #expect(result.isError != true)
        await client.disconnect()
    }

    @Test("the slow-build tool finishes as isError when told should_fail, with no reliance on wall-clock timing")
    func slowBuildToolHonorsShouldFailControl() async throws {
        let scripted = ScriptedServer()
        await scripted.addSlowBuildTool(totalSteps: Self.slowBuildFailureSteps, stepDelay: Self.slowBuildStepDelay)
        let client = try await connect(to: scripted)

        let result = try await client.callTool(
            name: ServerMode.slowBuildToolName, arguments: ["should_fail": .bool(true)])

        #expect(result.isError == true)
        await client.disconnect()
    }
}
