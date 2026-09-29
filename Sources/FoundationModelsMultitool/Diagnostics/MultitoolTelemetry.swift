// The tasks OTel 2 to OTel 7 read these names. This task adds the vocabulary
// before its readers, thus periphery must keep each declaration of the file.
// periphery:ignore:all

/// The telemetry vocabulary of the library target: the span names, the
/// attribute keys, the metric names with their dimension keys, the log label,
/// the log metadata keys and the constant log messages.
///
/// Rule 3 of the OpenTelemetry design of 2026-09-28: each package keeps all of
/// its telemetry names in one vocabulary file. No other source file of the
/// library target writes a telemetry name as a string literal. The model is
/// `RouterTelemetry` of FoundationModelsRouter.
///
/// Each name starts with the module name, `FoundationModelsMultitool.`, thus a
/// name of this library stays apart from the names of the host application
/// and of the other packages of the family. No two names are the same.
/// `MultitoolTelemetryTests` reads each name and fails on a name without the
/// prefix and on two equal names. A name here is part of the observable
/// surface of the library: a dashboard, a query or an alert of a host can
/// use it. Thus change a name only as a deliberate break.
///
/// The library uses the telemetry APIs only: `swift-distributed-tracing` for
/// spans, `swift-log` for logs and `swift-metrics` for metrics. It bootstraps
/// no backend. An executable bootstraps the backend. Until one does, each span
/// goes to a no-op tracer, each logger writes through the default handler of
/// swift-log, and each metric does nothing.
///
/// ## No content in the telemetry
///
/// A span attribute, a log message, a log metadata value and a metric
/// dimension value must never carry:
///
/// - prompt text or response text,
/// - tool arguments or tool output,
/// - JS source,
/// - embed input text,
/// - MCP payloads.
///
/// A span and a log record leave the process through the backend of the host,
/// and the library cannot know where that backend sends them. Identifiers,
/// names, counts and sizes are safe. Content is not safe. Thus each key below
/// names an identifier, a name, an outcome, a count or a size.
enum MultitoolTelemetry {
    /// The label of each logger of the library target.
    static let logLabel = "FoundationModelsMultitool.log"

    /// The name of each span that the library target opens.
    ///
    /// Each case names one call that can suspend for a long time. The span of
    /// the mounted tool call itself is not in this list: FoundationModelsExtras
    /// opens it with the name `FoundationModelsExtras.tool`.
    enum SpanName: String, CaseIterable, Sendable {
        /// One `runCode` call: `MultiTool.call(arguments:)`.
        case runCode = "FoundationModelsMultitool.runCode"

        /// One `searchTools` call: `SearchToolsTool.call(arguments:)`.
        case searchTools = "FoundationModelsMultitool.searchTools"

        /// One inner `tools.*` dispatch of a snippet:
        /// `RunBinding.invoke(_:arguments:journalOp:)`.
        case toolsDispatch = "FoundationModelsMultitool.tools.dispatch"

        /// One `respond(to:)` call of a selection session:
        /// `TracedAgentSession.respond(to:)`.
        case agentSessionRespond = "FoundationModelsMultitool.agent_session.respond"

        /// One `fork()` call of a selection session:
        /// `TracedAgentSession.fork()`.
        case agentSessionFork = "FoundationModelsMultitool.agent_session.fork"

        /// One client call to a tool of an MCP server:
        /// `MCPServer.call(name:arguments:)`.
        case mcpClientCall = "FoundationModelsMultitool.mcp.call"
    }

    /// The key of each attribute that a span of the library target carries.
    ///
    /// A metric dimension that records the same fact uses the same key (see
    /// ``MetricName/dimensionKeys``). Read the no-content rule of
    /// ``MultitoolTelemetry`` before you add a key.
    enum AttributeKey: String, CaseIterable, Sendable {
        /// The model-facing name of a tool: `runCode`, `searchTools`, or the
        /// `noun.verb` of an inner tool.
        case toolName = "FoundationModelsMultitool.tool.name"

        /// The verb of an inner `tools.<noun>.<verb>` call.
        case verb = "FoundationModelsMultitool.tool.verb"

        /// The journal operation of an inner call, when the call has one.
        case operation = "FoundationModelsMultitool.tool.operation"

        /// The noun of an inner `tools.<noun>.<verb>` call.
        case noun = "FoundationModelsMultitool.tool.noun"

        /// The name of an MCP server.
        case serverName = "FoundationModelsMultitool.mcp.server_name"

        /// How a call ended: for example `succeeded`, `failed`, `cancelled`,
        /// `timedOut` or `threw`.
        case outcome = "FoundationModelsMultitool.outcome"

        /// The kind of a failure: for example `transport`, `timeout`,
        /// `isError` or `protocol`.
        case errorKind = "FoundationModelsMultitool.error.kind"

        /// The completion token of the ambient tool call.
        case completionToken = "FoundationModelsMultitool.tool.completion_token"

        /// The nesting depth of a `runCode` call.
        case depth = "FoundationModelsMultitool.run_code.depth"

        /// The largest count of matches that a search can give.
        case searchLimit = "FoundationModelsMultitool.search.limit"

        /// The count of matches that a search gave.
        case matchCount = "FoundationModelsMultitool.search.match_count"

        /// The role of a selection session.
        case sessionRole = "FoundationModelsMultitool.agent_session.role"

        /// The size of a prompt, in characters.
        case promptCharacters = "FoundationModelsMultitool.agent_session.prompt_characters"

        /// The size of the instructions of a session, in characters.
        case instructionCharacters = "FoundationModelsMultitool.agent_session.instruction_characters"

        /// The size of the output of a tool call, in characters.
        case outputCharacters = "FoundationModelsMultitool.tool.output_characters"
    }

    /// The name of each metric that the library target records.
    ///
    /// FoundationModelsExtras records the metrics of the mounted tool call
    /// (`FoundationModelsExtras.tool.calls` and
    /// `FoundationModelsExtras.tool.duration`). The metrics here count the
    /// calls of the library itself, and each name starts with the prefix of
    /// this module.
    enum MetricName: String, CaseIterable, Sendable {
        /// The counter of the calls to `runCode`, to `searchTools` and to each
        /// inner `tools.*` verb.
        case toolCalls = "FoundationModelsMultitool.tool.calls"

        /// The timer of the calls that ``toolCalls`` counts.
        case toolDuration = "FoundationModelsMultitool.tool.duration"

        /// The counter of the failed calls to an MCP server.
        case mcpServerErrors = "FoundationModelsMultitool.mcp.server.errors"

        /// The counter of the restarts and the reconnects of an MCP server.
        case mcpServerRestarts = "FoundationModelsMultitool.mcp.server.restarts"

        /// The timer of each run of the JS interpreter.
        case interpreterRunDuration = "FoundationModelsMultitool.interpreter.run.duration"

        /// The keys of the dimensions of this metric, in order.
        ///
        /// Each value set of a dimension is small: tool names, server names,
        /// outcomes and error kinds. No metric has a dimension for a request
        /// id or a completion token, because those sets have no bound.
        var dimensionKeys: [AttributeKey] {
            switch self {
            case .toolCalls, .toolDuration:
                [.toolName, .outcome]
            case .mcpServerErrors:
                [.serverName, .errorKind]
            case .mcpServerRestarts:
                [.serverName]
            case .interpreterRunDuration:
                [.outcome]
            }
        }
    }

    /// The key of each log metadata value that no ``AttributeKey`` names.
    ///
    /// A log record that carries the fact of an attribute (for example the
    /// tool name or the server name) uses the ``AttributeKey`` of that fact.
    /// A log message is a constant text, and each variable value goes into
    /// the metadata under a key. An error goes into the metadata as its type
    /// and its code, never as its description, because a description can
    /// carry content.
    enum LogMetadataKey: String, CaseIterable, Sendable {
        /// The type of an error.
        case errorType = "FoundationModelsMultitool.error.type"

        /// The code of an error.
        case errorCode = "FoundationModelsMultitool.error.code"

        /// The name of an MCP method, for example `tools/call`.
        case methodName = "FoundationModelsMultitool.mcp.method"

        /// The id of an MCP request.
        case requestID = "FoundationModelsMultitool.mcp.request_id"

        /// A size, in bytes.
        case byteCount = "FoundationModelsMultitool.size.bytes"

        /// A count of items.
        case itemCount = "FoundationModelsMultitool.count.items"

        /// A size, in characters. For JS source it is the size only, never
        /// the source.
        case characterCount = "FoundationModelsMultitool.size.characters"

        /// A duration, in whole milliseconds.
        case durationMilliseconds = "FoundationModelsMultitool.duration.ms"

        /// The `tools.*` path that a snippet called and that the catalog does
        /// not have, without its `tools.` prefix. The model makes this name
        /// up. It is a name, not an argument and not a value.
        case imaginedPath = "FoundationModelsMultitool.hint.imagined_path"

        /// The tier that answered an imagined path: `resemblance`,
        /// `relevance`, `none` or `group`.
        case suggestionTier = "FoundationModelsMultitool.hint.tier"

        /// The catalog paths that the hint of an imagined path names, as an
        /// array of names.
        case suggestedPaths = "FoundationModelsMultitool.hint.suggested_paths"

        /// Where and why a schema element widened to `any`. The text holds
        /// schema names only: the property path, the `$ref` name or the type
        /// name. It holds no value, no description and no default of the
        /// schema.
        case wideningDetail = "FoundationModelsMultitool.schema.widening"

        /// The number of one connect attempt to an MCP server. The first
        /// attempt is `1`.
        case connectAttempt = "FoundationModelsMultitool.mcp.connect.attempt"

        /// The largest count of connect attempts that the backoff policy of a
        /// connect permits.
        case connectAttemptLimit = "FoundationModelsMultitool.mcp.connect.attempt_limit"

        /// The name that an MCP server gives for itself at `initialize`. It
        /// is a name, not a payload.
        case peerServerName = "FoundationModelsMultitool.mcp.peer_server_name"

        /// The wire id of a URL-mode elicitation.
        case elicitationID = "FoundationModelsMultitool.mcp.elicitation_id"
    }

    /// The message of each log record of the library target.
    ///
    /// A message is a constant text. Each variable value of a record goes into
    /// its metadata under a ``LogMetadataKey`` or an ``AttributeKey``. Thus a
    /// reader can find all records of one event with one message, and no
    /// message can carry content. A message is not a name of the vocabulary,
    /// thus it has no module prefix.
    enum LogMessage: String, CaseIterable, Sendable {
        /// One `tools.*` call of a snippet started. Level: `debug`.
        case toolInvocationStarted = "tools invocation started"

        /// One `tools.*` call of a snippet finished. Level: `debug`.
        case toolInvocationFinished = "tools invocation finished"

        /// The arguments of a `tools.*` call failed the validation before the
        /// call. Level: `warning`.
        case toolArgumentValidationFailed = "tools argument validation failed"

        /// The arguments of a `tools.*` call could not be marshaled. Level:
        /// `warning`.
        case toolArgumentMarshalingFailed = "tools argument marshaling failed"

        /// A `tools.*` call threw an error of the tool itself. Level: `error`.
        case toolInvocationFailed = "tools invocation failed"

        /// A snippet called a `tools.*` path that the catalog does not have.
        /// Level: `notice`. A host collects these records to learn the names
        /// that its model expects.
        case imaginedTool = "imaginedTool"

        /// The interpreter started one snippet. Level: `debug`.
        case snippetStarted = "runCode snippet started"

        /// The interpreter finished one snippet with a value. Level: `debug`.
        case snippetFinished = "runCode snippet finished"

        /// The interpreter ended one snippet with an error. Level: `debug`.
        case snippetEnded = "runCode snippet ended with an error"

        /// The renderer widened a schema element to `any`. Level: `warning`.
        case schemaWidened = "schema element widened to any"

        /// A rebuild of the surface after a change of an MCP server failed,
        /// and the old surface stays. Level: `warning`.
        case surfaceRebuildFailed = "surfaceRebuildFailed"

        /// One connect attempt to an MCP server succeeded. Level: `info`.
        case mcpConnectAttemptSucceeded = "mcp connect attempt succeeded"

        /// One connect attempt to an MCP server failed, and the backoff policy
        /// can retry it. Level: `warning`.
        case mcpConnectAttemptFailed = "mcp connect attempt failed"

        /// One connect attempt to an MCP server failed with a configuration
        /// error, and no retry follows. Level: `error`.
        case mcpConnectAttemptRefused = "mcp connect attempt failed with a configuration error"

        /// The connect waits for the backoff delay before the next attempt.
        /// Level: `info`.
        case mcpConnectRetryScheduled = "mcp connect retry scheduled"

        /// Each connect attempt that the backoff policy permits failed. Level:
        /// `error`.
        case mcpConnectBackoffExhausted = "mcp connect backoff exhausted"

        /// A host reconnect of an MCP server succeeded. Level: `info`.
        case mcpReconnected = "mcp server reconnected"

        /// The `initialize` handshake and the tool discovery of a connect
        /// succeeded. Level: `debug`.
        case mcpServerInitialized = "mcp server initialized"

        /// A newer connect attempt started, thus a stale attempt did not
        /// start its connect. Level: `warning`.
        case mcpStaleAttemptSkipped = "mcp stale connect attempt skipped"

        /// A newer connect attempt started, thus the success of a stale
        /// attempt was discarded. Level: `warning`.
        case mcpStaleSuccessDiscarded = "mcp stale connect success discarded"

        /// A newer connect attempt started, thus the failure of a stale
        /// attempt was discarded. Level: `warning`.
        case mcpStaleFailureDiscarded = "mcp stale connect failure discarded"

        /// A newer connect attempt started, thus the transport that a stale
        /// attempt built was discarded. Level: `warning`.
        case mcpStaleTransportDiscarded = "mcp stale transport discarded"

        /// A newer connect replaced a transport, thus the end of the receive
        /// stream of the old transport was ignored. Level: `warning`.
        case mcpStaleStreamEndIgnored = "mcp stale receive stream end ignored"

        /// The `notifications/cancelled` of a call could not be sent. Level:
        /// `warning`.
        case mcpCancelNoticeFailed = "mcp cancel notice failed"

        /// The transport of an MCP server dropped, and each call in flight
        /// failed as lost. Level: `warning`.
        case mcpTransportDropped = "mcp transport dropped"

        /// A URL-mode elicitation was declined because its url is not a URL.
        /// Level: `warning`.
        case mcpElicitationURLInvalid = "mcp url elicitation declined: the url is not valid"

        /// An elicitation through the calling run failed, and the answer is
        /// `cancel`. Level: `warning`.
        case mcpElicitationThroughRunFailed = "mcp elicitation through the calling run failed"

        /// A completion named an elicitation that the server does not hold.
        /// Level: `debug`.
        case mcpElicitationCompletionIgnored = "mcp elicitation completion ignored"

        /// A form-mode elicitation was declined because its schema is outside
        /// the restricted subset. Level: `warning`.
        case mcpElicitationSchemaDeclined = "mcp form elicitation declined: the schema is not supported"

        /// A `notifications/tools/list_changed` came in. Level: `debug`.
        case mcpToolListChanged = "mcp tools list changed"

        /// The re-list of the tools after a `tools/list_changed` failed.
        /// Level: `warning`.
        case mcpToolRelistFailed = "mcp tools re-list failed"
    }
}
