// `MCPServer+Call` — `call(name:arguments:)`, the one call method of
// `MCPServer`, on the run plane of Router.
//
// eventplan.md § "Phases", the phase-4 note: an MCP verb is a plain
// synchronous `Tool`. It runs inside the run that called it, so this method
// runs to completion, returns the `CallTool.Result` of the server, and mints
// no `completionToken` of its own. What the call needs from the run plane it
// reads off the ambient `ToolContext` — captured one time, at the start, the
// capture-at-start rule of eventplan.md § "The ambient context" — and a `nil`
// context is the bare-session path.
//
// **What replaced the sibling's call path.** The source
// (`../FoundationModelsMCP/Sources/FoundationModelsMCP/MCPServer.swift`) kept
// a soft deadline, a call handle, a running-call snapshot, retained records
// and three follow-up tools around every call. None of that is here. The
// engine of Router owns the run: its `timeout` is the clock, and every
// `notifications/progress` this file routes to `ToolContext.progress(_:)`
// resets it; cancellation of the calling `Task` becomes the advisory
// `notifications/cancelled` on the wire; a transport drop under an in-flight
// request throws `MCPServerError.lost`, a `LostRunError`, and `ToolRun`
// settles the calling run as `.lost`. A result with `isError: true` returns
// as a value, and the renderer keeps it in band.
//
// **The in-flight table.** Every request in flight stands in `inFlightCalls`
// under its request id, with the tool name, the captured context and — once
// the caller waits — its continuation. The id is minted here, and its string
// is the `progressToken` of the request, so one key finds the entry for a
// progress notification, for a cancel, and for the sweep a drop makes. The
// elicitation task routes a server request to the calling run through the
// same table.
//
// **The two in-band answers.** A server that is not `.ready` cannot carry a
// request, and a call with no ambient context has no engine to bound it.
// Neither is a `LostRunError` — nothing was in flight — and neither is thrown:
// each answers an `isError` result the model reads. The bare call is bounded
// by `callTimeout`, a fixed bound; the engine's clock, which progress resets,
// is what bounds every call made under a context, and this file keeps no
// clock for those.
//
// **What a drop leaves behind.** `MCP.Client` never resumes a pending request
// on its own when the transport drops — see `DropObservingTransport.swift` —
// so the task that relays the client's answer into the table waits until the
// next `connect(via:)` or `disconnect()` tears the client down. The call it
// served was settled long before, by the drop itself.

import FoundationModelsRouter
import MCP
import os

extension MCPServer {
    /// How one `tools/call` ends: the result the server answered, or the
    /// error the call throws.
    typealias CallSettlement = Result<CallTool.Result, any Error>

    /// One `tools/call` in flight — an entry of `inFlightCalls`, keyed by the
    /// request id.
    struct InFlightCall {
        /// Where the call stands between the request going out and its caller
        /// being resumed. The caller's wait and the settlement arrive in
        /// either order, and whichever comes second resumes the caller.
        enum Phase {
            /// The request went out; nobody waits yet, and nothing settled.
            case sent

            /// The caller waits on this continuation for the settlement.
            case awaited(CheckedContinuation<CallTool.Result, any Error>)

            /// The settlement arrived before the caller waited.
            case settled(CallSettlement)
        }

        /// The name of the tool the request names, for the diagnostics of
        /// every ending.
        let toolName: String

        /// The ambient context captured when the call started, or `nil` on
        /// the bare-session path.
        let context: ToolContext?

        /// Where the call stands — see ``Phase``.
        var phase: Phase = .sent

        /// The timer of a bare call — cancelled by the settlement, so a call
        /// that answered holds nothing open.
        var bareTimeout: Task<Void, Never>?
    }

    /// The key `registerNotificationHandlerOnce(_:register:)` records the
    /// `progress` registration under — see `setupHandlers()` in
    /// `MCPServer+Connection.swift`.
    static let progressHandlerName = "progress"

    /// What ``MCPServerError/lost(serverName:toolName:underlying:)`` carries
    /// when the transport dropped under the request.
    private static let transportDroppedDescription = "the transport dropped under the request"

    /// What the error carries when the transport had dropped before the
    /// request was sent, and no request went out.
    private static let transportAlreadyDroppedDescription =
        "the transport had dropped before the request was sent"

    /// What the error carries when the host's `disconnect()` tore the client
    /// down under the request.
    static let hostDisconnectedDescription = "the host disconnected the server under the request"

    /// The reason the `notifications/cancelled` of a cancelled calling `Task`
    /// carries.
    private static let taskCancelledReason = "the calling task was cancelled"

    /// The reason the `notifications/cancelled` of a timed-out bare call
    /// carries.
    private static let bareCallTimedOutReason = "the call exceeded the bare-call timeout"

    // MARK: - The call

    /// Calls the tool named `name` on the server, and returns its result.
    ///
    /// Runs to completion inside the run that called it. The ambient
    /// `ToolContext` is captured one time, at the start: every
    /// `notifications/progress` for this request reaches
    /// `ToolContext.progress(_:)` on that context, so the engine's clock
    /// resets, and the test sink of a run sees a `progress` event with the
    /// run's `correlationID`. A call with no ambient context routes no
    /// progress and is bounded by ``callTimeout`` instead.
    ///
    /// A result with `isError: true` returns as a value. So does the answer of
    /// a server that is not `.ready`, and the answer of a bare call that
    /// exceeded ``callTimeout``: each is an `isError` result, in band.
    ///
    /// - Parameters:
    ///   - name: The name of the tool to call.
    ///   - arguments: The arguments of the call, or `nil` for a tool that
    ///     takes none.
    /// - Returns: The result the server answered, or the in-band `isError`
    ///   result of a call that never reached it.
    /// - Throws: `CancellationError` when the calling `Task` was cancelled —
    ///   after `notifications/cancelled` went out for the request;
    ///   ``MCPServerError/lost(serverName:toolName:underlying:)`` when the
    ///   transport dropped under the request; otherwise the JSON-RPC error
    ///   the server answered with, unchanged.
    public func call(name: String, arguments: [String: Value]? = nil) async throws -> CallTool.Result {
        let context = ToolContext.current
        try Task.checkCancellation()
        guard case .ready = state else {
            return Self.toolErrorResult(toolName: name, reason: notReadyReason)
        }
        let requestID = ID.random
        inFlightCalls[requestID] = InFlightCall(toolName: name, context: context)
        return try await withTaskCancellationHandler {
            try await dispatch(name: name, arguments: arguments, requestID: requestID, context: context)
        } onCancel: {
            Task {
                await self.endInFlightCall(requestID: requestID, reason: Self.taskCancelledReason) { _ in
                    .failure(CancellationError())
                }
            }
        }
    }

    /// Sends the request registered under `requestID` and waits for its
    /// settlement.
    ///
    /// - Parameters:
    ///   - name: The name of the tool to call.
    ///   - arguments: The arguments of the call.
    ///   - requestID: The id of the request, and so its progress token.
    ///   - context: The captured ambient context, or `nil` on the bare path.
    /// - Returns: The settlement of the call.
    /// - Throws: What ``call(name:arguments:)`` throws.
    private func dispatch(
        name: String, arguments: [String: Value]?, requestID: ID, context: ToolContext?
    ) async throws -> CallTool.Result {
        guard !isTransportDropped else {
            inFlightCalls[requestID] = nil
            throw lostError(toolName: name, underlying: Self.transportAlreadyDroppedDescription)
        }
        let request = CallTool.request(
            id: requestID,
            .init(
                name: name, arguments: arguments,
                meta: Metadata(progressToken: .string(requestID.description))))
        let requestContext: RequestContext<CallTool.Result>
        do {
            requestContext = try await client.send(request)
        } catch {
            inFlightCalls[requestID] = nil
            throw classified(error, toolName: name)
        }
        Task { await self.relaySettlement(of: requestContext, into: requestID, toolName: name) }
        if context == nil {
            startBareTimeout(for: requestID)
        }
        return try await withCheckedThrowingContinuation { continuation in
            attachWaiter(continuation, to: requestID)
        }
    }

    // MARK: - The in-flight table

    /// Records `waiter` on the entry of `requestID`, or resumes it at once
    /// with the settlement that arrived first.
    ///
    /// One call attaches one waiter, to an entry `call(name:arguments:)`
    /// registered and `dispatch(name:arguments:requestID:context:)` removed
    /// only on a path that never waits. An entry that is missing, or that
    /// already holds a waiter, answers this waiter with a `CancellationError`
    /// all the same, so no caller waits forever — a graceful degradation,
    /// never a trap.
    ///
    /// - Parameters:
    ///   - waiter: The continuation of the caller.
    ///   - requestID: The id of the request the caller waits for.
    private func attachWaiter(
        _ waiter: CheckedContinuation<CallTool.Result, any Error>, to requestID: ID
    ) {
        switch inFlightCalls[requestID]?.phase {
        case .settled(let settlement)?:
            inFlightCalls[requestID] = nil
            waiter.resume(with: settlement)
        case .sent?:
            inFlightCalls[requestID]?.phase = .awaited(waiter)
        case .awaited?, nil:
            waiter.resume(throwing: CancellationError())
        }
    }

    /// Settles the call of `requestID`: resumes its waiter when one stands,
    /// else keeps `settlement` for the waiter to come — the one funnel every
    /// ending of a call goes through, and a second settlement is dropped.
    ///
    /// - Parameters:
    ///   - requestID: The id of the request that settled.
    ///   - settlement: The result, or the error, the call ends with.
    func settleInFlightCall(_ requestID: ID, with settlement: CallSettlement) {
        guard let entry = inFlightCalls[requestID] else { return }
        entry.bareTimeout?.cancel()
        switch entry.phase {
        case .awaited(let waiter):
            inFlightCalls[requestID] = nil
            waiter.resume(with: settlement)
        case .sent:
            inFlightCalls[requestID]?.phase = .settled(settlement)
        case .settled:
            break
        }
    }

    /// Awaits the answer of the client for `requestID` and settles the call
    /// with it — the task `dispatch(name:arguments:requestID:context:)`
    /// starts once the request went out.
    ///
    /// - Parameters:
    ///   - requestContext: The in-flight request of the client.
    ///   - requestID: The id of the request.
    ///   - toolName: The name of the tool, for the diagnostics of a failure.
    private func relaySettlement(
        of requestContext: RequestContext<CallTool.Result>, into requestID: ID, toolName: String
    ) async {
        do {
            let result = try await requestContext.value
            settleInFlightCall(requestID, with: .success(result))
        } catch {
            settleInFlightCall(requestID, with: .failure(classified(error, toolName: toolName)))
        }
    }

    /// Settles the call of `requestID` with what `settling` makes of its
    /// entry, then sends `notifications/cancelled` for it — the shared ending
    /// of a cancelled calling `Task` and of a timed-out bare call. A call
    /// that already settled is left alone.
    ///
    /// - Parameters:
    ///   - requestID: The id of the request to end.
    ///   - reason: The reason the cancellation notification carries.
    ///   - settling: Makes the settlement of the call from its entry.
    private func endInFlightCall(
        requestID: ID, reason: String, settling: (InFlightCall) -> CallSettlement
    ) async {
        guard let entry = inFlightCalls[requestID] else { return }
        settleInFlightCall(requestID, with: settling(entry))
        do {
            try await client.cancelRequest(requestID, reason: reason)
        } catch {
            logger.warning(
                "MCPServer \(self.identityNameForDiagnostics, privacy: .public) could not send notifications/cancelled: \(String(describing: error), privacy: .public)"
            )
        }
    }

    /// Fails every call in flight as
    /// ``MCPServerError/lost(serverName:toolName:underlying:)`` — the sweep
    /// a transport drop and a host disconnect each make.
    ///
    /// - Parameter underlying: What the error of each call carries.
    func failInFlightCalls(underlying: String) {
        for (requestID, entry) in inFlightCalls {
            settleInFlightCall(
                requestID,
                with: .failure(lostError(toolName: entry.toolName, underlying: underlying)))
        }
    }

    // MARK: - The transport drop

    /// What the end of the receive stream of the connected transport reaches
    /// — see `DropObservingTransport.swift`. Records the drop and fails every
    /// call in flight, when `generation` is still current; a report from a
    /// transport a newer connect superseded is discarded.
    ///
    /// The `state` stays as it was, and no catalog snapshot is emitted: the
    /// recovery is the host's `reconnect()`, which discovers afresh and emits
    /// the one snapshot of the returning server.
    ///
    /// - Parameter generation: The `connectGeneration` the transport was
    ///   connected under.
    func handleTransportDrop(generation: Int) {
        guard
            isCurrentGeneration(
                generation, orDiscard: "ignoring the end of a receive stream a newer connect superseded")
        else {
            return
        }
        isTransportDropped = true
        logger.warning(
            "MCPServer \(self.identityNameForDiagnostics, privacy: .public) transport dropped with \(self.inFlightCalls.count) calls in flight"
        )
        failInFlightCalls(underlying: Self.transportDroppedDescription)
    }

    /// The error a call ends with, given what the client threw.
    ///
    /// A cancelled request is a `CancellationError`. A connection-level
    /// failure — `connectionClosed`, `transportError`, and the client's own
    /// `internalError` once the transport is known to have dropped — is the
    /// loss. Every other error is the JSON-RPC error the server answered
    /// with, and it stands unchanged.
    ///
    /// - Parameters:
    ///   - error: What the client threw.
    ///   - toolName: The name of the tool, for the diagnostics of the loss.
    /// - Returns: The error the call throws.
    private func classified(_ error: any Error, toolName: String) -> any Error {
        if error is CancellationError {
            return CancellationError()
        }
        guard let mcpError = error as? MCPError else { return error }
        switch mcpError {
        case .connectionClosed, .transportError:
            return lostError(toolName: toolName, underlying: String(describing: mcpError))
        case .internalError where isTransportDropped:
            return lostError(toolName: toolName, underlying: String(describing: mcpError))
        default:
            return error
        }
    }

    /// The loss of one call, named for this server.
    ///
    /// - Parameters:
    ///   - toolName: The name of the tool the request named.
    ///   - underlying: What the error carries.
    /// - Returns: The error.
    private func lostError(toolName: String, underlying: String) -> MCPServerError {
        .lost(serverName: identityNameForDiagnostics, toolName: toolName, underlying: underlying)
    }

    // MARK: - The bare call

    /// Starts the timer of a call made with no ambient context: once
    /// ``callTimeout`` elapses with the call still in flight, the call ends
    /// with an in-band `isError` result and `notifications/cancelled` goes
    /// out for the request.
    ///
    /// - Parameter requestID: The id of the bare request.
    private func startBareTimeout(for requestID: ID) {
        let timeout = callTimeout
        let timer = Task {
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            await self.endInFlightCall(requestID: requestID, reason: Self.bareCallTimedOutReason) {
                entry in
                .success(Self.toolErrorResult(toolName: entry.toolName, reason: self.timedOutReason))
            }
        }
        inFlightCalls[requestID]?.bareTimeout = timer
    }

    // MARK: - Progress

    /// What one inbound `notifications/progress` reaches: the context of the
    /// call its token names, when that call is in flight and was made under
    /// one. A token that names no in-flight call, and a call made with no
    /// context, route nothing.
    ///
    /// - Parameter parameters: The inbound `notifications/progress` payload.
    func handleProgressNotification(parameters: ProgressNotification.Parameters) async {
        guard
            let entry = inFlightCalls[Self.requestID(of: parameters.progressToken)],
            let context = entry.context
        else {
            return
        }
        await context.progress(Self.progressDetail(toolName: entry.toolName, parameters: parameters))
    }

    /// The request id a progress token names — the inverse of the token
    /// `dispatch(name:arguments:requestID:context:)` sends.
    ///
    /// - Parameter token: The token of the notification.
    /// - Returns: The id.
    private static func requestID(of token: ProgressToken) -> ID {
        switch token {
        case .string(let text):
            return .string(text)
        case .integer(let number):
            return .number(number)
        }
    }

    /// The `detail` of the `progress` event one notification posts.
    ///
    /// - Parameters:
    ///   - toolName: The name of the tool the call names.
    ///   - parameters: The inbound `notifications/progress` payload.
    /// - Returns: The detail.
    private static func progressDetail(
        toolName: String, parameters: ProgressNotification.Parameters
    ) -> String {
        var detail = "\(toolName): \(parameters.progress)"
        if let total = parameters.total {
            detail += " of \(total)"
        }
        if let message = parameters.message {
            detail += " — \(message)"
        }
        return detail
    }

    // MARK: - The in-band results

    /// Builds the `isError` result of a call that never reached the server,
    /// or that the server never answered.
    ///
    /// - Parameters:
    ///   - toolName: The name of the tool the call names.
    ///   - reason: What went wrong, as the tail of the sentence.
    /// - Returns: The result, with `isError` set.
    private static func toolErrorResult(toolName: String, reason: String) -> CallTool.Result {
        CallTool.Result(
            content: [.text(text: "Tool \"\(toolName)\" \(reason)", annotations: nil, _meta: nil)],
            isError: true)
    }

    /// The reason of the in-band result of a call on a server that is not
    /// `.ready`.
    private var notReadyReason: String {
        "is not available: server \"\(identityNameForDiagnostics)\" is \(String(describing: state))."
    }

    /// The reason of the in-band result of a bare call that exceeded
    /// ``callTimeout``.
    private var timedOutReason: String {
        "did not answer within \(String(describing: callTimeout)); the request was cancelled."
    }
}
