import Metrics

/// The helpers that record each metric of the library target.
///
/// ## Make each metric at the time of the record
///
/// Each helper makes its `Counter` or `Timer` when it records, and never keeps
/// one in a `static let`. `MetricsSystem.factory` gives the factory that the
/// current task binds with `withMetricsFactory`, or else the factory that the
/// host bootstrapped. A metric keeps the factory of the time that the code made
/// it. Thus a metric in a `static let` goes to the factory of the first task
/// that touched it, and never to the factory of a later task, for example a
/// test capture.
///
/// ## Which tool calls the library counts
///
/// FoundationModelsExtras records `FoundationModelsExtras.tool.calls` and
/// `FoundationModelsExtras.tool.duration` for each call of a mounted tool: the
/// `runCode` call, the `searchTools` call, and each inner `tools.*` call that
/// a session context mounts through `RunBinding.innerCallMount`. The library
/// does not count these calls a second time. It counts only the inner
/// `tools.*` call that no mount holds: the native call of
/// `ToolInvoker.invoke(_:content:binding:journalOp:)` when no session bound a
/// context.
///
/// ## No content in a dimension
///
/// Each dimension value is a name or a fixed word of the vocabulary: a tool
/// name, a server name, an ``MultitoolTelemetry/OutcomeValue`` or an
/// ``MultitoolTelemetry/ErrorKindValue``. No dimension carries a request id or
/// a completion token, because those sets have no bound.
extension MultitoolTelemetry {
    /// Runs one native inner `tools.*` call, and records one count on
    /// ``MetricName/toolCalls`` and one duration on ``MetricName/toolDuration``
    /// when it ends.
    ///
    /// - Parameters:
    ///   - toolName: The model-facing name of the inner tool.
    ///   - body: The call.
    /// - Returns: The value of `body`.
    /// - Throws: The error of `body`, unchanged.
    nonisolated(nonsending) static func measuringToolCall<Output>(
        toolName: String, _ body: nonisolated(nonsending) () async throws -> Output
    ) async throws -> Output {
        let start = ContinuousClock.now
        do {
            let output = try await body()
            recordToolCall(toolName: toolName, outcome: .succeeded, duration: ContinuousClock.now - start)
            return output
        } catch {
            recordToolCall(toolName: toolName, outcome: outcome(of: error), duration: ContinuousClock.now - start)
            throw error
        }
    }

    /// Records one native inner `tools.*` call: one count on
    /// ``MetricName/toolCalls`` and one duration on ``MetricName/toolDuration``.
    ///
    /// - Parameters:
    ///   - toolName: The model-facing name of the inner tool.
    ///   - outcome: How the call ended.
    ///   - duration: The duration of the call.
    private static func recordToolCall(toolName: String, outcome: OutcomeValue, duration: Duration) {
        let values: [AttributeKey: String] = [.toolName: toolName, .outcome: outcome.rawValue]
        Counter(label: MetricName.toolCalls.rawValue, dimensions: dimensions(of: .toolCalls, values)).increment()
        Metrics.Timer(label: MetricName.toolDuration.rawValue, dimensions: dimensions(of: .toolDuration, values))
            .record(duration: duration)
    }

    /// Records one failed call to an MCP server on
    /// ``MetricName/mcpServerErrors``.
    ///
    /// - Parameters:
    ///   - serverName: The name of the server.
    ///   - kind: The kind of the failure. The client span of the call carries
    ///     the same value under ``AttributeKey/errorKind``.
    static func recordMCPServerError(serverName: String, kind: ErrorKindValue) {
        let values: [AttributeKey: String] = [.serverName: serverName, .errorKind: kind.rawValue]
        Counter(label: MetricName.mcpServerErrors.rawValue, dimensions: dimensions(of: .mcpServerErrors, values))
            .increment()
    }

    /// Records one restart or reconnect of an MCP server on
    /// ``MetricName/mcpServerRestarts``.
    ///
    /// - Parameter serverName: The name of the server.
    static func recordMCPServerRestart(serverName: String) {
        let values: [AttributeKey: String] = [.serverName: serverName]
        Counter(label: MetricName.mcpServerRestarts.rawValue, dimensions: dimensions(of: .mcpServerRestarts, values))
            .increment()
    }

    /// Records one run of the JS interpreter on
    /// ``MetricName/interpreterRunDuration``.
    ///
    /// The interpreter runs on a queue of its own, which has no task-local
    /// value. Thus the caller reads `MetricsSystem.factory` in the thread
    /// that started the run, and gives it here.
    ///
    /// - Parameters:
    ///   - outcome: How the run ended.
    ///   - duration: The duration of the run.
    ///   - factory: The metrics factory of the thread that started the run.
    static func recordInterpreterRun(outcome: OutcomeValue, duration: Duration, factory: any MetricsFactory) {
        let values: [AttributeKey: String] = [.outcome: outcome.rawValue]
        Metrics.Timer(
            label: MetricName.interpreterRunDuration.rawValue,
            dimensions: dimensions(of: .interpreterRunDuration, values),
            factory: factory
        )
        .record(duration: duration)
    }

    /// The dimensions of `metric`, in the order of
    /// ``MetricName/dimensionKeys``.
    ///
    /// - Parameters:
    ///   - metric: The metric.
    ///   - values: The value of each dimension key of `metric`. A key with no
    ///     value gives no dimension.
    /// - Returns: The dimensions, under the raw values of the keys.
    private static func dimensions(of metric: MetricName, _ values: [AttributeKey: String]) -> [(String, String)] {
        metric.dimensionKeys.compactMap { key in
            values[key].map { (key.rawValue, $0) }
        }
    }
}
