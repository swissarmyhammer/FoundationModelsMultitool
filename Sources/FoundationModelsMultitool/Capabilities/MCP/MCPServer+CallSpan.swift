// `MCPServer+CallSpan` — the client span of each `tools/call`, and the W3C
// trace context that the request carries to the server.
//
// The OpenTelemetry design of 2026-09-28: the trace context goes across a
// process boundary as W3C `traceparent` and `tracestate` in the `_meta` of the
// MCP request. Each MCP call has one client span. A span attribute carries no
// MCP payload, no tool argument and no tool output.
//
// **The span.** `call(name:arguments:)` opens the span through
// `MultitoolTelemetry.traced`, thus through `TracedCall.run` of
// FoundationModelsExtras. The span is a child of the current span, for example
// the span of a `tools.*` dispatch. `TracedCall.run` also writes one "enter"
// log record when the call starts: a call can wait for a long time, for
// example for a slow tool or for an elicitation.
//
// **The trace context.** The tracer of the task injects the context of the
// client span into the `_meta` of the request, next to the progress token.
// This file writes no `traceparent` format of its own: the tracer writes the
// fields, and their names, for example `traceparent` and `tracestate`.
//
// **The error status.** A thrown error gives the error status through
// `Tracer.withSpan`. A call that does not throw can also fail: a bare call
// that timed out, and a result with `isError` set. This file gives each of
// them the error status.
//
// **The events.** A transport drop and a reconnect during a call are events
// on the span of each call in flight, not new spans.

import Foundation
import MCP
import Tracing

extension MCPServer {
    /// Runs one `tools/call` in a client span, and writes one "enter" log
    /// record when the call starts.
    ///
    /// The span carries the server name, the tool name and the request id at
    /// its start. When the call returns, the span also carries the count and
    /// the size of the content of the result. When the call throws, the span
    /// carries the kind of the error.
    ///
    /// - Parameters:
    ///   - toolName: The name of the MCP tool.
    ///   - requestID: The id of the request.
    ///   - body: The call. It gets the open span.
    /// - Returns: The result of `body`.
    /// - Throws: The error of `body`.
    func withCallSpan(
        toolName: String, requestID: ID,
        _ body: nonisolated(nonsending) (any Span) async throws -> CallTool.Result
    ) async throws -> CallTool.Result {
        let serverName = identityNameForDiagnostics
        let requestIDText = requestID.description
        let metadata = MultitoolTelemetry.serverNameMetadata(serverName)
            .merging(MultitoolTelemetry.toolNameMetadata(toolName)) { first, _ in first }
            .merging([MultitoolTelemetry.AttributeKey.requestID.rawValue: "\(requestIDText)"]) { first, _ in first }
        return try await MultitoolTelemetry.traced(
            .mcpClientCall, ofKind: .client, logger: logger,
            attributes: [.serverName: serverName, .toolName: toolName, .requestID: requestIDText],
            metadata: metadata
        ) { span in
            do {
                let result = try await body(span)
                Self.recordEnding(of: result, on: span)
                recordError(kind: endingErrorKind(of: result, requestID: requestID))
                return result
            } catch {
                let kind = Self.errorKind(of: error)
                span.attributes.set([.errorKind: kind?.rawValue])
                recordError(kind: kind)
                throw error
            }
        }
    }

    /// Records one failed call on the error counter of this server.
    ///
    /// The error counter reads no span attribute: a no-op span keeps no
    /// attributes, and a host with no tracer still records metrics. The kind
    /// is the same ``MultitoolTelemetry/ErrorKindValue`` that the client span
    /// carries, thus the two do not drift.
    ///
    /// - Parameter kind: The kind of the failure, or `nil` for a call that
    ///   did not fail, or that was cancelled.
    private func recordError(kind: MultitoolTelemetry.ErrorKindValue?) {
        guard let kind else {
            return
        }
        MultitoolTelemetry.recordMCPServerError(serverName: identityNameForDiagnostics, kind: kind)
    }

    /// The kind of the failure of a call that returned `result`.
    ///
    /// Removes `requestID` from ``timedOutRequestIDs``, because the call has
    /// ended.
    ///
    /// - Parameters:
    ///   - result: The result of the call.
    ///   - requestID: The id of the request.
    /// - Returns: ``MultitoolTelemetry/ErrorKindValue/timeout`` for a bare
    ///   call that timed out, ``MultitoolTelemetry/ErrorKindValue/isError``
    ///   for another result with `isError` set, or else `nil`.
    private func endingErrorKind(
        of result: CallTool.Result, requestID: ID
    ) -> MultitoolTelemetry.ErrorKindValue? {
        let timedOut = timedOutRequestIDs.remove(requestID) != nil
        guard result.isError == true else {
            return nil
        }
        return timedOut ? .timeout : .isError
    }

    /// The `_meta` of one `tools/call` request: the progress token, and the
    /// trace context of `span`.
    ///
    /// The instrument of the task writes the trace context. A W3C tracer
    /// writes `traceparent`, and `tracestate` when the trace has one. A tracer
    /// that injects nothing, for example the no-op tracer, leaves the progress
    /// token alone.
    ///
    /// - Parameters:
    ///   - requestID: The id of the request. Its text is the progress token.
    ///   - span: The client span of the call.
    /// - Returns: The `_meta` of the request.
    static func requestMetadata(requestID: ID, span: any Span) -> Metadata {
        var metadata = Metadata(progressToken: .string(requestID.description))
        InstrumentationSystem.instrument.inject(span.context, into: &metadata, using: MetadataInjector())
        return metadata
    }

    /// Gives the span of a bare call the outcome and the kind of a timeout,
    /// and marks the request as timed out for the error counter.
    ///
    /// The bare call then returns an `isError` result.
    /// ``recordEnding(of:on:)`` keeps this outcome on the span, and the error
    /// counter records the kind `timeout`, not `isError`.
    ///
    /// - Parameters:
    ///   - requestID: The id of the request.
    ///   - span: The client span of the call.
    func recordTimeout(of requestID: ID, on span: any Span) {
        timedOutRequestIDs.insert(requestID)
        span.attributes.set([
            .outcome: MultitoolTelemetry.OutcomeValue.timedOut.rawValue,
            .errorKind: MultitoolTelemetry.ErrorKindValue.timeout.rawValue,
        ])
    }

    /// Records `event` on the span of each call in flight.
    ///
    /// - Parameter event: The name of the event.
    func recordEventOnInFlightCalls(_ event: MultitoolTelemetry.SpanEventName) {
        for entry in inFlightCalls.values {
            entry.span.addEvent(SpanEvent(name: event.rawValue))
        }
    }

    /// Records the start of a connect: the span event
    /// ``MultitoolTelemetry/SpanEventName/mcpReconnectStarted`` on each call
    /// in flight, and one count on the restart counter when the server
    /// connected before.
    ///
    /// A connect is a restart or a reconnect when an earlier connect
    /// succeeded, that is, when the server has an ``identity``. The first
    /// connect is not a restart. A stdio server restarts through this same
    /// connect, because its transport factory is `StdioServerProcess.respawn`.
    /// Thus `respawn` records no count of its own: a second count there would
    /// count each restart two times.
    func recordConnectStart() {
        recordEventOnInFlightCalls(.mcpReconnectStarted)
        guard identity != nil else {
            return
        }
        MultitoolTelemetry.recordMCPServerRestart(serverName: identityNameForDiagnostics)
    }

    /// Records the count and the size of the content of `result` on `span`,
    /// and the error status when `result` has `isError` set.
    ///
    /// An `isError` result gets ``MultitoolTelemetry/OutcomeValue/failed``
    /// and ``MultitoolTelemetry/ErrorKindValue/isError``, unless the span
    /// already has an outcome, for example the outcome of a timeout.
    ///
    /// - Parameters:
    ///   - result: The result of the call.
    ///   - span: The client span of the call.
    private static func recordEnding(of result: CallTool.Result, on span: any Span) {
        span.attributes.set([
            .contentCount: result.content.count,
            .contentBytes: encodedByteCount(of: result.content),
        ])
        guard result.isError == true else {
            return
        }
        span.setStatus(SpanStatus(code: .error))
        guard span.attributes.get(MultitoolTelemetry.AttributeKey.outcome.rawValue) == nil else {
            return
        }
        span.attributes.set([
            .outcome: MultitoolTelemetry.OutcomeValue.failed.rawValue,
            .errorKind: MultitoolTelemetry.ErrorKindValue.isError.rawValue,
        ])
    }

    /// The size of `content`: the count of bytes of its JSON encoding.
    ///
    /// The size is a count, not content, thus a span can carry it.
    ///
    /// - Parameter content: The content blocks of a result.
    /// - Returns: The count of bytes, or `nil` when the content does not
    ///   encode. Then the span gets no size.
    private static func encodedByteCount(of content: [MCP.Tool.Content]) -> Int? {
        (try? JSONEncoder().encode(content))?.count
    }

    /// The kind of the error that a call threw.
    ///
    /// - Parameter error: The error of the call.
    /// - Returns: ``MultitoolTelemetry/ErrorKindValue/transport`` for a lost
    ///   call, `nil` for a `CancellationError`, because its outcome tells the
    ///   cancel, or else ``MultitoolTelemetry/ErrorKindValue/protocolError``.
    private static func errorKind(of error: any Error) -> MultitoolTelemetry.ErrorKindValue? {
        if case MCPServerError.lost = error {
            return .transport
        }
        return error is CancellationError ? nil : .protocolError
    }
}

/// Writes each field that an instrument injects into the `_meta` of an MCP
/// request, as a string value.
private struct MetadataInjector: Injector {
    /// Writes `value` under `key`.
    ///
    /// - Parameters:
    ///   - value: The value, for example a `traceparent` value.
    ///   - key: The key, for example `traceparent`.
    ///   - carrier: The `_meta` of the request.
    func inject(_ value: String, forKey key: String, into carrier: inout Metadata) {
        carrier.fields[key] = .string(value)
    }
}
