import FoundationModelsExtras
import Logging
import Tracing

/// The helpers that each span of the library target uses.
///
/// ## Why each span also writes an "enter" log record
///
/// A suspended Swift `async` function occupies no OS thread. Thus `sample`,
/// `spindump` and a crash report show nothing of a call that waits in an
/// `await`. A tracing backend exports a span only when the span ends, and a
/// call that hangs never ends. Thus each asynchronous span of the library
/// opens through `TracedCall.run` of FoundationModelsExtras, which writes one
/// "enter" log record when the span starts. The logging backend exports that
/// record at once.
///
/// ## Reading a hang
///
/// Look in the logs of the host for the records with the message
/// `enter <span name>`. Each record holds the `trace.id` and the `span.id` of
/// its span. Look in the traces for the ended spans with the same ids. Spans
/// nest, thus one hang leaves more than one enter record with no ended span.
/// The LAST enter record with no ended span names the call that started and
/// did not return.
extension MultitoolTelemetry {
    /// Runs one asynchronous call in a span, and writes one "enter" log
    /// record when the call starts.
    ///
    /// The span opens through `TracedCall.run` of FoundationModelsExtras, with
    /// the tracer of the current task. The span is a child of the span of the
    /// current `ServiceContext`. The span gets ``AttributeKey/outcome`` when
    /// the call ends: ``OutcomeValue/succeeded`` when `body` returns and set
    /// no outcome itself, or the outcome of the error when `body` throws. When
    /// the call throws, the span records the error and gets the error status,
    /// and this function throws the same error.
    ///
    /// Give no content in `attributes` and in `metadata`: ids, names, counts
    /// and sizes only.
    ///
    /// - Parameters:
    ///   - spanName: The name of the span.
    ///   - kind: The kind of the span. The default is `.internal`.
    ///   - spanLogger: The logger of the "enter" record. The default is
    ///     ``logger``.
    ///   - attributes: The attributes of the span, set before `body` starts. A
    ///     `nil` value sets no attribute.
    ///   - metadata: The metadata of the "enter" record.
    ///   - body: The call. It gets the open span, so that it can add an
    ///     attribute that it knows only at its end, for example an outcome
    ///     that is not ``OutcomeValue/succeeded``.
    /// - Returns: The value of `body`.
    /// - Throws: The error of `body`.
    nonisolated(nonsending) static func traced<Output>(
        _ spanName: SpanName,
        ofKind kind: SpanKind = .internal,
        logger spanLogger: Logger = MultitoolTelemetry.logger,
        attributes: [AttributeKey: (any SpanAttributeConvertible)?] = [:],
        metadata: Logger.Metadata = [:],
        _ body: nonisolated(nonsending) (any Span) async throws -> Output
    ) async throws -> Output {
        try await TracedCall.run(spanName.rawValue, ofKind: kind, logger: spanLogger, metadata: metadata) { span in
            span.updateAttributes { $0.set(attributes) }
            do {
                let output = try await body(span)
                if span.attributes.get(AttributeKey.outcome.rawValue) == nil {
                    span.attributes[AttributeKey.outcome.rawValue] = OutcomeValue.succeeded.rawValue
                }
                return output
            } catch {
                span.attributes[AttributeKey.outcome.rawValue] = MultitoolTelemetry.outcome(of: error).rawValue
                throw error
            }
        }
    }

    /// Runs one synchronous call in a span.
    ///
    /// `TracedCall.run` is asynchronous, thus a synchronous call cannot use
    /// it, and this span writes no "enter" record. A synchronous call that
    /// blocks holds its thread, thus `sample` and `spindump` show it.
    ///
    /// - Parameters:
    ///   - spanName: The name of the span.
    ///   - attributes: The attributes of the span. Ids, names, counts and
    ///     sizes only. A `nil` value sets no attribute.
    ///   - body: The call.
    /// - Returns: The value of `body`.
    /// - Throws: The error of `body`. The span records it first.
    static func tracedSynchronously<Output>(
        _ spanName: SpanName,
        attributes: [AttributeKey: (any SpanAttributeConvertible)?] = [:],
        _ body: () throws -> Output
    ) rethrows -> Output {
        try InstrumentationSystem.tracer.withSpan(spanName.rawValue, ofKind: .internal) { span in
            span.updateAttributes { $0.set(attributes) }
            return try body()
        }
    }

    /// The span attributes of the journal op of an inner `tools.*` call.
    ///
    /// - Parameter journalOp: The `"verb noun"` op of the call (see
    ///   `APISurface.Entry.journalOp`), or `nil` for a tool that is
    ///   registered under no noun.
    /// - Returns: The op under ``AttributeKey/operation``, its verb under
    ///   ``AttributeKey/verb`` and its noun under ``AttributeKey/noun``. Each
    ///   value is `nil` when `journalOp` is `nil`.
    static func journalAttributes(of journalOp: String?) -> [AttributeKey: (any SpanAttributeConvertible)?] {
        let words = journalOp?.split(separator: " ", maxSplits: 1).map(String.init)
        return [.operation: journalOp, .verb: words?.first, .noun: words?.dropFirst().first]
    }

    /// The outcome value of a call that threw `error`.
    ///
    /// - Parameter error: The error of the call.
    /// - Returns: ``OutcomeValue/cancelled`` for a `CancellationError`, or else
    ///   ``OutcomeValue/threw``.
    static func outcome(of error: any Error) -> OutcomeValue {
        error is CancellationError ? .cancelled : .threw
    }
}

extension SpanAttributes {
    /// Sets each attribute of `attributes` that has a value.
    ///
    /// - Parameter attributes: The attributes, under the keys of the
    ///   vocabulary. A `nil` value sets no attribute.
    mutating func set(_ attributes: [MultitoolTelemetry.AttributeKey: (any SpanAttributeConvertible)?]) {
        for (key, value) in attributes {
            self[key.rawValue] = value
        }
    }
}

extension MultitoolTelemetry {
    /// The telemetry of one task, kept as a value so that another task can
    /// use it.
    ///
    /// The interpreter runs each `tools.*` call of a snippet in a task that it
    /// starts on its own thread. That task has no task-local value of the
    /// `runCode` call: no `ServiceContext`, no tracer that `withTracer` binds,
    /// and no ``boundLogger``. Thus `MultiTool` captures a scope in the task
    /// of the `runCode` call, in the `runCode` span, and binds it again around
    /// each host function (see ``bind(_:)``). The span of each `tools.*` call
    /// is then a child of the `runCode` span, and its records go to the logger
    /// of the call.
    struct Scope: Sendable {
        /// The tracer of the captured task.
        let tracer: any Tracer

        /// The service context of the captured task, with its current span.
        /// `nil` when the task had none.
        let serviceContext: ServiceContext?

        /// The logger of the captured task.
        let logger: Logger

        /// The scope of the current task.
        static var current: Scope {
            Scope(tracer: InstrumentationSystem.tracer, serviceContext: .current, logger: MultitoolTelemetry.logger)
        }

        /// Wraps `function` so that it runs in this scope, from whichever task
        /// calls it. The wrapper keeps the same name.
        ///
        /// - Parameter function: The host function to wrap.
        /// - Returns: The wrapped host function.
        func bind(_ function: AsyncHostFunction) -> AsyncHostFunction {
            AsyncHostFunction(name: function.name) { arguments in
                try await withTracer(tracer) {
                    try await ServiceContext.withValue(serviceContext) {
                        try await MultitoolTelemetry.$boundLogger.withValue(logger) {
                            try await function.call(arguments)
                        }
                    }
                }
            }
        }
    }
}
