// `ScriptedServer` — a scriptable `MCP.Server` the MCP suites run against.
//
// A behavioral port of
// `../FoundationModelsMCP/Sources/MCPTestServer/ScriptedServer.swift`.
// eventplan.md § "Consolidation of the siblings" moves the MCP capability
// into this package, and the tests of that capability need a server they
// can script: register a tool, remove it, re-schema it, page `tools/list`,
// send `notifications/tools/list_changed` in a burst, elicit mid-call, report
// progress mid-call, drop the transport mid-call, and record the
// notifications the client sends.
//
// **Test support, not a shipped type.** This target is a product only so
// that `IntegrationTests/`, a separate package, can import it — see
// `testServerTargetName` in `Package.swift`. The library target of this
// package never links it.
//
// **What is not ported.** The source's `withResolvedSelf` guard threw when a
// weak `self` had gone. It stays, because the wrapped `MCP.Server` retains
// its handlers and a strong capture would cycle. The source's references to
// `Examples/` targets are gone: this package ships no examples.
//
// **The types are `public`.** A product exports its surface, and the two
// consumers of this one — the unit test target and the nested integration
// package — are other modules. Every public item carries a doc comment.

import Foundation
import MCP

/// A scriptable `MCP.Server` test double.
///
/// `MCP.Server` is a concrete `actor` of the swift-sdk with a fixed
/// `withMethodHandler` / `onNotification` registration surface, and it has
/// no concept of a scripted scenario. `ScriptedServer` wraps one `Server`,
/// owns the `tools/list` / `tools/call` dispatch pair over a mutable tool
/// registry (``addTool(_:)``, ``removeTool(named:)``, ``replaceTool(_:)``),
/// and layers scenario factories over that registry — the echo tool, the
/// filesystem tools, the progress tools, the eliciting tools, and the
/// transport-dropping tool — so that a test drives each scenario from plain
/// async code against a real `MCP.Client`.
public actor ScriptedServer {
    /// The error message a handler throws when its weak `self` capture is
    /// gone — one string, so every such guard reports the same words.
    private static let deallocatedErrorMessage = "ScriptedServer deallocated"

    /// How many milliseconds ``waitForRecordedNotifications(count:timeout:)``
    /// waits between two reads of ``recordedNotifications``.
    private static let recordedNotificationPollMilliseconds = 5

    /// How often ``waitForRecordedNotifications(count:timeout:)`` re-reads
    /// ``recordedNotifications`` while it polls.
    private static let recordedNotificationPollInterval = Duration.milliseconds(
        recordedNotificationPollMilliseconds)

    /// Runs `body` with the resolved instance of a `[weak self]` capture, or
    /// throws ``deallocatedErrorMessage`` when the server is gone.
    ///
    /// Every handler closure below captures `self` weakly, because the
    /// wrapped `MCP.Server` retains the closure and a strong capture would
    /// cycle. Swift permits the `guard let self` sugar only as an
    /// optional-binding condition, so the resolved instance goes to `body`
    /// as a parameter.
    ///
    /// - Parameters:
    ///   - weakSelf: The captured `self`, an optional under `[weak self]`.
    ///   - body: Runs with the resolved, non-optional server.
    /// - Returns: What `body` returns.
    /// - Throws: `MCPError.internalError(deallocatedErrorMessage)` when
    ///   `weakSelf` is `nil`; otherwise what `body` throws.
    private static func withResolvedSelf<T>(
        _ weakSelf: ScriptedServer?,
        _ body: (ScriptedServer) async throws -> T
    ) async throws -> T {
        guard let weakSelf else {
            throw MCPError.internalError(deallocatedErrorMessage)
        }
        return try await body(weakSelf)
    }

    /// The wrapped swift-sdk server that speaks the MCP protocol.
    private let server: MCP.Server

    /// The transport the server was started with, kept so that
    /// ``dropTransport()`` can sever the connection on command.
    private var transport: (any Transport)?

    /// The tool registry, in registration order — the order `tools/list`
    /// pagination walks.
    private var tools: [ScriptedTool] = []

    /// The maximum number of tools per `tools/list` page, or `nil` for every
    /// tool in one page.
    private let toolsPageSize: Int?

    /// Every inbound notification this server observed, in receipt order.
    /// See ``RecordedNotification`` for what is captured.
    public private(set) var recordedNotifications: [RecordedNotification] = []

    /// Creates a scripted server around a fresh `MCP.Server`.
    ///
    /// - Parameters:
    ///   - name: The server name reported at `initialize`.
    ///   - version: The server version reported at `initialize`.
    ///   - toolsPageSize: The maximum tools per `tools/list` page. `nil`,
    ///     the default, returns every registered tool in one page.
    ///   - capabilities: The capabilities to advertise. The default declares
    ///     `tools(listChanged: true)`, because ``emitToolListChanged()`` and
    ///     ``emitToolListChangedBurst(count:)`` exist to exercise it.
    public init(
        name: String = "ScriptedServer",
        version: String = "1.0.0",
        toolsPageSize: Int? = nil,
        capabilities: MCP.Server.Capabilities = .init(tools: .init(listChanged: true))
    ) {
        self.toolsPageSize = toolsPageSize
        self.server = MCP.Server(name: name, version: version, capabilities: capabilities)
    }

    // MARK: - Lifecycle

    /// Registers the `tools/list`, `tools/call` and cancellation-recording
    /// handlers, then starts the wrapped server on `transport`.
    ///
    /// - Parameter transport: The transport to serve on — one end of an
    ///   `InMemoryTransport` pair in a test, or a `StdioTransport` in the
    ///   `mcp-test-server` executable.
    /// - Throws: What `MCP.Server.start(transport:)` throws.
    public func start(transport: any Transport) async throws {
        self.transport = transport
        await registerHandlers()
        try await server.start(transport: transport)
    }

    /// Blocks until the message loop of the wrapped server ends.
    ///
    /// The `mcp-test-server` executable calls this to stay alive for the
    /// life of a stdio connection.
    public func waitUntilCompleted() async {
        await server.waitUntilCompleted()
    }

    /// Disconnects the transport the server was started with — a transport
    /// drop, on command from a test or from inside a tool handler (see
    /// ``addTransportDroppingTool(named:)``).
    public func dropTransport() async {
        await transport?.disconnect()
    }

    /// Registers the three handlers ``start(transport:)`` installs.
    private func registerHandlers() async {
        await server.withMethodHandler(ListTools.self) { [weak self] params in
            try await Self.withResolvedSelf(self) { instance in
                await instance.listToolsPage(cursor: params.cursor)
            }
        }

        await server.withMethodHandler(CallTool.self) { [weak self] params in
            try await Self.withResolvedSelf(self) { instance in
                try await instance.dispatchCallTool(params)
            }
        }

        await server.onNotification(CancelledNotification.self) { [weak self] message in
            guard let self else { return }
            await self.recordNotification(
                method: CancelledNotification.name,
                requestId: message.params.requestId,
                reason: message.params.reason
            )
        }
    }

    // MARK: - Tool registry

    /// Adds one tool to the registry, after every tool already there.
    ///
    /// A tool with the same name stays in place and `tool` is appended as a
    /// second entry; ``replaceTool(_:)`` updates a tool in place.
    ///
    /// - Parameter tool: The definition and handler to register.
    public func addTool(_ tool: ScriptedTool) {
        tools.append(tool)
    }

    /// Removes every registered tool with the given name.
    ///
    /// - Parameter name: The tool name to remove.
    public func removeTool(named name: String) {
        tools.removeAll { $0.definition.name == name }
    }

    /// Replaces the tool named `tool.definition.name` in place, or appends
    /// `tool` when no tool has that name — the primitive behind "re-schema a
    /// tool on command".
    ///
    /// - Parameter tool: The replacement definition and handler.
    public func replaceTool(_ tool: ScriptedTool) {
        if let index = tools.firstIndex(where: { $0.definition.name == tool.definition.name }) {
            tools[index] = tool
        } else {
            tools.append(tool)
        }
    }

    /// Builds an `MCP.Tool` from `name`, `description` and `inputSchema` and
    /// registers it with `handler` — the plumbing every scripted tool
    /// factory shares, so each one spells out only what differs.
    ///
    /// - Parameters:
    ///   - name: The tool name.
    ///   - description: The tool description.
    ///   - inputSchema: The input JSON Schema of the tool.
    ///   - handler: The closure that answers `tools/call` for this tool.
    func addScriptedTool(
        name: String,
        description: String,
        inputSchema: Value,
        handler: @escaping @Sendable (CallTool.Parameters) async throws -> CallTool.Result
    ) {
        addTool(
            ScriptedTool(
                definition: MCP.Tool(name: name, description: description, inputSchema: inputSchema),
                handler: handler
            )
        )
    }

    /// Schedules `mutation` — an ``addTool(_:)``, a ``removeTool(named:)``, a
    /// ``replaceTool(_:)``, or a mix — to run after `delay`: the "on a timer"
    /// half of the tool-mutation scenario.
    ///
    /// The task is unstructured on purpose. The caller returns at once and
    /// observes the mutation from the far side of the connection, so no
    /// scope can await it; it ends by itself once `mutation` returns, and it
    /// holds `self` weakly, so it never keeps a released server alive.
    ///
    /// - Parameters:
    ///   - delay: How long to wait before `mutation` runs.
    ///   - mutation: The mutation to apply, given the live server.
    public func scheduleMutation(
        after delay: Duration,
        _ mutation: @escaping @Sendable (ScriptedServer) async -> Void
    ) {
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self else { return }
            await mutation(self)
        }
    }

    /// Answers one `tools/list` request: every tool when ``toolsPageSize`` is
    /// `nil`, otherwise the page `cursor` names.
    ///
    /// - Parameter cursor: The cursor of the previous page, or `nil` for the
    ///   first page.
    /// - Returns: The page, with a `nextCursor` when more tools follow.
    private func listToolsPage(cursor: String?) -> ListTools.Result {
        let startIndex = cursor.flatMap(Int.init) ?? 0
        guard startIndex >= 0, startIndex <= tools.count else {
            return ListTools.Result(tools: [])
        }
        guard let pageSize = toolsPageSize else {
            return ListTools.Result(tools: tools.map(\.definition))
        }
        let endIndex = min(startIndex + pageSize, tools.count)
        let page = tools[startIndex..<endIndex].map(\.definition)
        let nextCursor = endIndex < tools.count ? String(endIndex) : nil
        return ListTools.Result(tools: page, nextCursor: nextCursor)
    }

    /// Answers one `tools/call` request through the handler of the named
    /// tool.
    ///
    /// - Parameter params: The call parameters.
    /// - Returns: What the handler of the tool returns.
    /// - Throws: `MCPError.invalidParams` when no tool has that name;
    ///   otherwise what the handler throws.
    private func dispatchCallTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let tool = tools.first(where: { $0.definition.name == params.name }) else {
            throw MCPError.invalidParams("Unknown tool: \(params.name)")
        }
        return try await tool.handler(params)
    }

    // MARK: - tools/list_changed

    /// Sends one `notifications/tools/list_changed` notification.
    ///
    /// - Throws: What `MCP.Server.notify(_:)` throws.
    public func emitToolListChanged() async throws {
        try await server.notify(ToolListChangedNotification.message())
    }

    /// Sends `count` `notifications/tools/list_changed` notifications back
    /// to back, with no delay between them — a "rapid burst".
    ///
    /// - Parameter count: How many notifications to send.
    /// - Throws: What the first failing ``emitToolListChanged()`` throws;
    ///   the burst stops there.
    public func emitToolListChangedBurst(count: Int) async throws {
        for _ in 0..<count {
            try await emitToolListChanged()
        }
    }

    // MARK: - Progress

    /// Registers a tool that sends `totalSteps` progress notifications,
    /// `stepDelay` apart, before it returns — "periodic
    /// `notifications/progress` during a long call".
    ///
    /// Progress goes out only when the caller opted in with a
    /// `progressToken` in the `_meta` of the call, as the spec requires;
    /// otherwise the tool waits out the same total duration and returns.
    ///
    /// - Parameters:
    ///   - name: The tool name.
    ///   - totalSteps: How many progress notifications to send.
    ///   - stepDelay: How long to wait between notifications.
    public func addProgressReportingTool(
        named name: String,
        totalSteps: Int,
        stepDelay: Duration
    ) {
        addProgressTool(
            named: name,
            description: "Reports progress over \(totalSteps) steps before completing.",
            totalSteps: totalSteps,
            stepDelay: stepDelay,
            perCallIdentity: nil)
    }

    /// Registers a tool that mints a fresh identity for every call, reports
    /// that identity as the `message` of each of its `totalSteps` progress
    /// notifications, and returns it as the result — so a test can tell two
    /// concurrent calls to the same tool apart from the far side.
    ///
    /// The identity is the server's own and has no relation to the progress
    /// token of the caller, which is what makes it an independent check that
    /// a client-side correlation key really keys each progress update to its
    /// call. Otherwise the same as
    /// ``addProgressReportingTool(named:totalSteps:stepDelay:)``, including
    /// the opt-in contract.
    ///
    /// - Parameters:
    ///   - name: The tool name.
    ///   - totalSteps: How many progress notifications to send.
    ///   - stepDelay: How long to wait between notifications.
    public func addCallIdentifyingProgressTool(
        named name: String,
        totalSteps: Int,
        stepDelay: Duration
    ) {
        addProgressTool(
            named: name,
            description: "Reports its own per-call identity over \(totalSteps) steps before completing.",
            totalSteps: totalSteps,
            stepDelay: stepDelay,
            perCallIdentity: { UUID().uuidString })
    }

    /// The result text of ``addProgressReportingTool(named:totalSteps:stepDelay:)``,
    /// which has no per-call identity to report.
    private static let progressToolCompletionText = "done"

    /// The registration ``addProgressReportingTool(named:totalSteps:stepDelay:)``
    /// and ``addCallIdentifyingProgressTool(named:totalSteps:stepDelay:)``
    /// share; the two differ only in the text one call reports and returns.
    ///
    /// - Parameters:
    ///   - name: The tool name.
    ///   - description: The model-facing description.
    ///   - totalSteps: How many progress notifications to send.
    ///   - stepDelay: How long to wait between notifications.
    ///   - perCallIdentity: Mints, once per call, the text that call reports
    ///     as every progress `message` and returns as its result; `nil`
    ///     reports no message and returns `progressToolCompletionText`.
    private func addProgressTool(
        named name: String,
        description: String,
        totalSteps: Int,
        stepDelay: Duration,
        perCallIdentity: (@Sendable () -> String)?
    ) {
        addScriptedTool(
            name: name,
            description: description,
            inputSchema: JSONSchemaBuilder.emptySchema
        ) { [weak self] params in
            try await Self.withResolvedSelf(self) { instance in
                let identity = perCallIdentity?()
                try await instance.conditionallyReportProgress(
                    params: params, totalSteps: totalSteps, stepDelay: stepDelay
                ) { token in
                    try await instance.sendProgressNotifications(
                        token: token, totalSteps: totalSteps, stepDelay: stepDelay
                    ) { _ in identity }
                }
                let text = identity ?? Self.progressToolCompletionText
                return CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)])
            }
        }
    }

    /// Sends `totalSteps` `notifications/progress` notifications, `stepDelay`
    /// apart — the loop every progress-reporting tool shares.
    ///
    /// - Parameters:
    ///   - token: The progress token the caller sent in the `_meta` of the
    ///     call.
    ///   - totalSteps: How many notifications to send.
    ///   - stepDelay: How long to wait between notifications.
    ///   - messageForStep: The `message` for a given 1-based step. The
    ///     default reports no message.
    /// - Throws: What `MCP.Server.notify(_:)` throws.
    private func sendProgressNotifications(
        token: ProgressToken, totalSteps: Int, stepDelay: Duration,
        messageForStep: (Int) -> String? = { _ in nil }
    ) async throws {
        for step in 1...totalSteps {
            try await server.notify(
                ProgressNotification.message(
                    .init(
                        progressToken: token, progress: Double(step),
                        total: Double(totalSteps), message: messageForStep(step))))
            try await Task.sleep(for: stepDelay)
        }
    }

    /// Reports progress when the caller opted in with a `progressToken`, or
    /// waits out the same total duration — the opt-in-or-wait branch every
    /// progress-reporting handler shares.
    ///
    /// - Parameters:
    ///   - params: The call parameters; `_meta.progressToken` decides.
    ///   - totalSteps: How many steps the wait-only branch accounts for.
    ///   - stepDelay: How long each step accounts for in the wait-only
    ///     branch.
    ///   - notify: Sends this tool's own `notifications/progress` sequence,
    ///     given the token of the caller.
    /// - Throws: What `notify` throws.
    private func conditionallyReportProgress(
        params: CallTool.Parameters,
        totalSteps: Int,
        stepDelay: Duration,
        _ notify: (ProgressToken) async throws -> Void
    ) async throws {
        if let token = params._meta?.progressToken {
            try await notify(token)
        } else {
            try await Task.sleep(for: stepDelay * totalSteps)
        }
    }

    // MARK: - Slow build

    /// The build-phase labels the slow-build tool cycles through in its
    /// progress `message`, so a run reads like a build log and not a bare
    /// step counter.
    private static let slowBuildPhases = [
        "Resolving package dependencies",
        "Compiling Swift sources",
        "Linking binary",
        "Running unit tests",
        "Packaging artifact",
    ]

    /// The argument the slow-build tool reads to decide its terminal
    /// outcome — an argument, never a wall-clock guess; see
    /// ``addSlowBuildTool(named:totalSteps:stepDelay:)``.
    private static let slowBuildShouldFailArgument = "should_fail"

    /// The `inputSchema` of the slow-build tool: one optional boolean flag,
    /// its only caller-facing control.
    private static let slowBuildInputSchema: Value = JSONSchemaBuilder.object(
        properties: [
            slowBuildShouldFailArgument: .object([
                "type": .string("boolean"),
                "description": .string(
                    "If true, the build reports isError once its steps finish, instead of succeeding."
                ),
            ])
        ]
    )

    /// The default step count of ``addSlowBuildTool(named:totalSteps:stepDelay:)``.
    ///
    /// `public`, like ``ServerMode/slowBuildToolName``: a default argument of
    /// a public function must be at least as visible as the function, because
    /// Swift resolves defaults at the call site, in other modules too.
    public static let defaultSlowBuildStepCount = 20

    /// The default delay between steps of
    /// ``addSlowBuildTool(named:totalSteps:stepDelay:)`` — one second, so the
    /// default shape reports about once a second for about twenty seconds.
    ///
    /// `public` — see ``defaultSlowBuildStepCount``.
    public static let defaultSlowBuildStepDelay = Duration.seconds(1)

    /// Registers a tool that simulates a multi-step build: `totalSteps`
    /// `notifications/progress` updates, `stepDelay` apart, each naming its
    /// phase (``slowBuildPhases``), then a success — or, when the caller
    /// passed `should_fail: true`, an `isError` result.
    ///
    /// The outcome is controlled by argument, not by wall-clock timing: the
    /// caller decides the terminal outcome at call time, so a test built on
    /// it is deterministic. `totalSteps` and `stepDelay` are factory
    /// parameters, the shape ``addProgressReportingTool(named:totalSteps:stepDelay:)``
    /// takes, so a test registers a fast instance instead of waiting out the
    /// default run.
    ///
    /// - Parameters:
    ///   - name: The tool name. Defaults to ``ServerMode/slowBuildToolName``.
    ///   - totalSteps: How many progress notifications to send. Defaults to
    ///     ``defaultSlowBuildStepCount``.
    ///   - stepDelay: How long to wait between notifications. Defaults to
    ///     ``defaultSlowBuildStepDelay``.
    public func addSlowBuildTool(
        named name: String = ServerMode.slowBuildToolName,
        totalSteps: Int = ScriptedServer.defaultSlowBuildStepCount,
        stepDelay: Duration = ScriptedServer.defaultSlowBuildStepDelay
    ) {
        addScriptedTool(
            name: name,
            description:
                "Simulates a multi-step build, reporting its current phase via notifications/progress at every step. Pass should_fail: true to have it finish as isError instead of succeeding.",
            inputSchema: Self.slowBuildInputSchema
        ) { [weak self] params in
            try await Self.withResolvedSelf(self) { instance in
                try await instance.conditionallyReportProgress(
                    params: params, totalSteps: totalSteps, stepDelay: stepDelay
                ) { token in
                    try await instance.sendSlowBuildProgress(
                        token: token, totalSteps: totalSteps, stepDelay: stepDelay)
                }
                let shouldFail = params.arguments?[Self.slowBuildShouldFailArgument]?.boolValue ?? false
                return Self.slowBuildResult(totalSteps: totalSteps, shouldFail: shouldFail)
            }
        }
    }

    /// Sends `totalSteps` progress updates, `stepDelay` apart, each naming
    /// its build phase — ``sendProgressNotifications(token:totalSteps:stepDelay:messageForStep:)``
    /// with a step-dependent message.
    ///
    /// - Parameters:
    ///   - token: The progress token of the caller.
    ///   - totalSteps: How many notifications to send.
    ///   - stepDelay: How long to wait between notifications.
    /// - Throws: What `MCP.Server.notify(_:)` throws.
    private func sendSlowBuildProgress(
        token: ProgressToken, totalSteps: Int, stepDelay: Duration
    ) async throws {
        try await sendProgressNotifications(token: token, totalSteps: totalSteps, stepDelay: stepDelay) { step in
            Self.slowBuildPhaseMessage(step: step, totalSteps: totalSteps)
        }
    }

    /// The progress `message` for `step` of `totalSteps` — cycles through
    /// ``slowBuildPhases``.
    ///
    /// - Parameters:
    ///   - step: The 1-based step number.
    ///   - totalSteps: The total step count.
    /// - Returns: The rendered message.
    private static func slowBuildPhaseMessage(step: Int, totalSteps: Int) -> String {
        let phase = slowBuildPhases[(step - 1) % slowBuildPhases.count]
        return "\(phase) (step \(step) of \(totalSteps))"
    }

    /// The terminal `tools/call` result of the slow-build tool.
    ///
    /// - Parameters:
    ///   - totalSteps: How many steps the build ran, for the message.
    ///   - shouldFail: Whether the caller asked for a failure.
    /// - Returns: An `isError` result when `shouldFail`, otherwise a success.
    private static func slowBuildResult(totalSteps: Int, shouldFail: Bool) -> CallTool.Result {
        guard shouldFail else {
            return CallTool.Result(
                content: [.text(text: "Build succeeded after \(totalSteps) steps.", annotations: nil, _meta: nil)])
        }
        return CallTool.Result(
            content: [
                .text(
                    text: "Build failed after \(totalSteps) steps: should_fail was set for this call.",
                    annotations: nil, _meta: nil)
            ],
            isError: true)
    }

    // MARK: - Elicitation

    /// Registers a tool that elicits user input mid-call through a form-mode
    /// `elicitation/create`, then reflects the elicitation result in its own
    /// `tools/call` result — a full elicit round trip.
    ///
    /// - Parameters:
    ///   - name: The tool name.
    ///   - message: The message shown to the user in the prompt.
    ///   - requestedSchema: The schema of the elicited response.
    ///   - preElicitationDelay: How long to sleep before the
    ///     `elicitation/create` goes out. A nonzero value lets a soft
    ///     deadline of the test elapse first, so the call has detached by
    ///     the time it elicits. Defaults to `.zero`.
    ///   - postElicitationStall: How long to sleep after the elicitation
    ///     resolves, before the `tools/call` response goes out. Lets a test
    ///     prove that a call deadline restarted from the moment the
    ///     elicitation was answered. Defaults to `.zero`.
    public func addElicitingTool(
        named name: String,
        message: String,
        requestedSchema: Elicitation.RequestSchema,
        preElicitationDelay: Duration = .zero,
        postElicitationStall: Duration = .zero
    ) {
        addScriptedTool(
            name: name,
            description: "Elicits user input mid-call and echoes it back.",
            inputSchema: JSONSchemaBuilder.emptySchema
        ) { [weak self] _ in
            try await Self.withResolvedSelf(self) { instance in
                if preElicitationDelay > .zero {
                    try await Task.sleep(for: preElicitationDelay)
                }
                let result = try await instance.server.requestElicitation(
                    message: message, requestedSchema: requestedSchema)
                if postElicitationStall > .zero {
                    try await Task.sleep(for: postElicitationStall)
                }
                return Self.buildElicitationResult(from: result)
            }
        }
    }

    /// Builds the `tools/call` result an eliciting tool returns once its
    /// `elicitation/create` resolves — shared by the form-mode and the
    /// URL-mode tools, which differ in how they request and not in how they
    /// report.
    ///
    /// - Parameter result: The elicitation result.
    /// - Returns: A result naming the action taken, with the elicited
    ///   content, if any, as `structuredContent`.
    private static func buildElicitationResult(from result: CreateElicitation.Result) -> CallTool.Result {
        let structuredContent: Value? = result.content.map(Value.object)
        return CallTool.Result(
            content: [
                .text(text: "elicitation \(result.action.rawValue)", annotations: nil, _meta: nil)
            ],
            structuredContent: structuredContent
        )
    }

    /// Registers a tool that sends a URL-mode `elicitation/create` mid-call
    /// — `URLParameters { message, mode: .url, url, elicitationId }` — then
    /// reflects the result in its own `tools/call` result: the URL-mode
    /// mirror of ``addElicitingTool(named:message:requestedSchema:preElicitationDelay:postElicitationStall:)``.
    ///
    /// - Parameters:
    ///   - name: The tool name.
    ///   - message: The message shown to the user in the prompt.
    ///   - url: The link the user visits to complete the request.
    ///   - elicitationId: The identifier the `URLParameters.elicitationId`
    ///     of this request carries.
    public func addURLElicitingTool(
        named name: String,
        message: String,
        url: String,
        elicitationId: String
    ) {
        addScriptedTool(
            name: name,
            description: "Elicits user input mid-call via a URL and echoes it back.",
            inputSchema: JSONSchemaBuilder.emptySchema
        ) { [weak self] _ in
            try await Self.withResolvedSelf(self) { instance in
                let result = try await instance.server.requestElicitation(
                    message: message, url: url, elicitationId: elicitationId)
                return Self.buildElicitationResult(from: result)
            }
        }
    }

    /// Sends one `notifications/elicitation/complete` notification — the
    /// third message of the URL-mode elicitation flow, which tells the
    /// client that the out-of-band interaction has finished.
    ///
    /// - Parameter elicitationId: The elicitation id the notification names.
    /// - Throws: What `MCP.Server.notify(_:)` throws.
    public func sendElicitationComplete(elicitationId: String) async throws {
        try await server.notify(ElicitationCompleteNotification.message(.init(elicitationId: elicitationId)))
    }

    // MARK: - Transport drop mid-call

    /// Registers a tool that drops the transport as its first action and
    /// never answers — "transport drop mid-call" as something a tool call
    /// triggers, not only something a test drives through
    /// ``dropTransport()``.
    ///
    /// - Parameter name: The tool name.
    public func addTransportDroppingTool(named name: String) {
        addScriptedTool(
            name: name,
            description: "Drops the transport connection mid-call.",
            inputSchema: JSONSchemaBuilder.emptySchema
        ) { [weak self] _ in
            try await Self.withResolvedSelf(self) { instance in
                await instance.dropTransport()
                throw MCPError.connectionClosed
            }
        }
    }

    // MARK: - Recorded notifications

    /// Appends one recorded notification.
    ///
    /// Not a trivial wrapper: `recordedNotifications` is actor-isolated
    /// mutable state, and a `[weak self]` notification closure that runs off
    /// the actor cannot append to it directly. This method is the isolation
    /// boundary.
    ///
    /// - Parameters:
    ///   - method: The JSON-RPC notification method.
    ///   - requestId: The id of the cancelled request, when carried.
    ///   - reason: The cancellation reason, when carried.
    private func recordNotification(method: String, requestId: ID?, reason: String?) {
        recordedNotifications.append(
            RecordedNotification(method: method, requestId: requestId, reason: reason))
    }

    /// Polls ``recordedNotifications`` until at least `count` have arrived,
    /// or `timeout` elapses.
    ///
    /// The message-handling task of the wrapped server drives the recording,
    /// so there is no signal a test can await; a bounded poll observes it
    /// without a fixed sleep.
    ///
    /// - Parameters:
    ///   - count: The minimum number of recorded notifications to wait for.
    ///   - timeout: The maximum time to wait.
    /// - Returns: ``recordedNotifications`` at the moment `count` was
    ///   reached, or at the moment `timeout` elapsed, whichever came first.
    public func waitForRecordedNotifications(
        count: Int, timeout: Duration
    ) async -> [RecordedNotification] {
        let deadline = ContinuousClock.now + timeout
        while recordedNotifications.count < count && ContinuousClock.now < deadline {
            try? await Task.sleep(for: Self.recordedNotificationPollInterval)
        }
        return recordedNotifications
    }
}

/// One inbound notification ``ScriptedServer`` observed from a connected
/// client, recorded for a test to assert on.
///
/// Only `notifications/cancelled` is recorded today: it is the one inbound
/// notification a scripted test double needs to observe. To record another
/// method later is one more `onNotification` registration that appends the
/// same struct.
public struct RecordedNotification: Sendable, Equatable {
    /// The JSON-RPC notification method, for example
    /// `"notifications/cancelled"`.
    public let method: String

    /// The id of the cancelled request, when the notification carried one.
    public let requestId: ID?

    /// The human-readable cancellation reason, when the notification carried
    /// one.
    public let reason: String?
}
