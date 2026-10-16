// `MCPServer+Elicitation` — the passthrough of a server-initiated
// `elicitation/create` to the one elicitation machinery of
// FoundationModelsExtras, and the relay of
// `notifications/elicitation/complete`.
//
// eventplan.md § "Phases", phase 4: "The `ElicitationCoordinator` protocol
// becomes the host seam of `ToolContext.elicit`, URL mode included." The
// sibling's `ElicitationCoordinator` and `MCPElicitationTool` are gone.
// The `ElicitationRequest` / `ElicitationResponse` pair and the `RunPlane` of
// FoundationModelsExtras are the one machinery; this file decodes the wire request
// into the first, and encodes the second back onto the wire.
//
// **Three answerers, one order.** A question needs an answerer, and the verb
// is a plain `Tool` that must work on a bare `LanguageModelSession` too:
//
// 1. The `ToolContext` the calling run captured — `MCPServer.call(name:arguments:)`
//    records it in the in-flight table. The request goes to the call that
//    its `_meta.progressToken` names, else to the one run that has all the
//    calls in flight; never to a guess among several runs (see
//    `callingContext(linkedBy:)`). `context.elicit(_:)` suspends the run on
//    the run plane of the session. The answer is not held.
// 2. Else the host's `elicitationHandler` — the bare-session path. Apple's
//    tool call holds the turn while the user answers: the ordinary cost of a
//    plain tool on a plain session.
// 3. Else `cancel` to the server, with the reason in `_meta`, and a log
//    record. Never a throw into the transport.
//
// A bound context wins when present, so a Router host never sets the handler.
//
// **A headless session asks no one.** When the `userPresence` of this actor
// is `.headless`, each request gets `cancel` at once, with
// `RunPlane.noUserPresentReason` under the `reason` key of `_meta`. The
// three answerers are not asked. Each decline and each cancel that gives a
// reason carries it the same way.
//
// **The restricted form schema.** eventplan.md: "Our boundary enforces the
// restricted form schema for each elicitor." The wire schema is decoded by
// the `ElicitationRequestedSchema` of FoundationModelsExtras, which refuses a
// nested object and
// every type outside the subset; a request that fails that decode answers
// `decline`, with a log line.
//
// **URL mode is a three-message flow**, and both answerers hold the accept
// until the flow ends. Under a context, the `RunPlane` keeps the run
// suspended after the accept until the flow completes, so the accept reaches
// the wire only after the flow closed. Under the handler, this actor holds
// the accept the same way until `complete(elicitationId:)`.
//
// **The relay of the completion.** The swift-sdk client runs a request
// handler inline in its message loop, so the loop reads no wire message while
// the handler is held. Thus the `DropObservingTransport` of the attempt reads
// each `notifications/elicitation/complete` before the loop does, and awaits
// `complete(elicitationId:generation:)` before it yields the next frame. That
// function ends the flow in this order:
//
// 1. A held accept of the handler, keyed by the wire id.
// 2. An open question of a bound context, keyed by the wire id in
//    `pendingContextElicitations` and of the same connect generation: the
//    completion goes to `ToolContext.complete(elicitationId:)` with the
//    `ToolContext` id that this actor chose for the question.
// 3. Else the completion is ignored, per the spec.
//
// A completion that comes before the accept gives `noPendingElicitation`, and
// the entry stays. A completion after the run ended is ignored: the entry
// left the map when `elicit(_:through:)` returned. `complete(elicitationId:)`
// is the one end of a held flow, whether the host calls it or the relay does.

import Foundation
import FoundationModelsExtras
import Logging
import MCP
import ULID

extension MCPServer {
    /// The host's answerer for a bare session — case 2 of the resolution
    /// order in the header of this file. Never called while a `ToolContext`
    /// is bound around the call the request belongs to.
    public typealias ElicitationHandler = @Sendable (ElicitationRequest) async -> ElicitationResponse

    // MARK: - The handler the client calls

    /// Registers the `elicitation/create` handler on `client`, the new client
    /// of one connect attempt — the one registration `setupHandlers(on:)`
    /// makes for a request, beside the notification handlers.
    ///
    /// `[weak self]`, as `registerNotificationHandler(_:on:handler:)`
    /// captures: the client retains the closure, and this actor retains the
    /// client. A request that arrives after this actor is gone answers
    /// `cancel`, so the server never waits on a host that no longer exists.
    ///
    /// - Parameter client: The client to register the handler on.
    func registerElicitationHandler(on client: MCP.Client) async {
        await client.withElicitationHandler { [weak self] parameters in
            guard let self else {
                return MCPServer.wireResult(of: .cancel)
            }
            return await self.answerElicitation(parameters: parameters)
        }
    }

    /// Answers one `elicitation/create`: decodes the wire request into
    /// an `ElicitationRequest`, resolves it in the order the header of
    /// this file states, and encodes the answer back onto the wire.
    ///
    /// In a headless session (``userPresence`` is `.headless`), no person
    /// can answer. The answer is a cancel with `RunPlane.noUserPresentReason`
    /// at once: before the schema decode, the context and the host's
    /// handler.
    ///
    /// - Parameter parameters: The request as the server sent it — form
    ///   mode with a `requestedSchema`, or URL mode with a `url` and an
    ///   `elicitationId`.
    /// - Returns: The result the server reads.
    func answerElicitation(parameters: CreateElicitation.Parameters) async -> CreateElicitation.Result {
        guard userPresence == .interactive else {
            record(.mcpElicitationCancelledNoUserPresent, level: .debug)
            return Self.wireResult(of: .cancel(reason: RunPlane.noUserPresentReason))
        }
        switch parameters {
        case .form(let form):
            guard let requestedSchema = decodeRestrictedSchema(form.requestedSchema) else {
                return Self.wireResult(of: .decline)
            }
            let request = ElicitationRequest(
                message: form.message, elicitationId: ULID(), requestedSchema: requestedSchema)
            return Self.wireResult(of: await resolve(request, urlElicitationId: nil, linkedBy: form._meta))
        case .url(let url):
            guard let link = URL(string: url.url) else {
                // The url is content of the server, thus the record holds the
                // wire id of the elicitation and not the url.
                record(
                    .mcpElicitationURLInvalid, level: .warning,
                    metadata: [MultitoolTelemetry.LogMetadataKey.elicitationID.rawValue: "\(url.elicitationId)"])
                return Self.wireResult(of: .decline)
            }
            let request = ElicitationRequest(message: url.message, elicitationId: ULID(), url: link)
            return Self.wireResult(
                of: await resolve(request, urlElicitationId: url.elicitationId, linkedBy: url._meta))
        }
    }

    // MARK: - The resolution order

    /// Resolves `request` through the first answerer that stands: the
    /// calling run's context, else the host's handler, else `cancel` with
    /// the reason.
    ///
    /// - Parameters:
    ///   - request: The decoded request.
    ///   - urlElicitationId: The wire `elicitationId` of a URL-mode request,
    ///     which a held accept under the handler is keyed by; `nil` in form
    ///     mode.
    ///   - meta: The `_meta` of the request, which can name the call of the
    ///     question by its progress token.
    /// - Returns: The answer.
    private func resolve(
        _ request: ElicitationRequest, urlElicitationId: String?, linkedBy meta: Metadata?
    ) async -> ElicitationResponse {
        if let context = callingContext(linkedBy: meta) {
            guard let urlElicitationId,
                openContextElicitation(urlElicitationId, request: request, context: context)
            else {
                return await elicit(request, through: context)
            }
            defer { pendingContextElicitations.removeValue(forKey: urlElicitationId) }
            return await elicit(request, through: context)
        }
        guard let elicitationHandler else {
            return cancelWithNoAnswerer()
        }
        let response = await elicitationHandler(request)
        if let urlElicitationId, response.action == .accept {
            await awaitHostCompletion(of: urlElicitationId)
        }
        return response
    }

    /// The context of the call that a server elicitation belongs to, or
    /// `nil` when no context can answer it. The rules, in order:
    ///
    /// 1. When `meta` has the standard `progressToken` key and the token
    ///    names a call in flight that was made under a context, the context
    ///    of that call.
    /// 2. Else, when all calls in flight were made under the context of one
    ///    run, that context. Thus one call in flight gives its context. A
    ///    token that names no call in flight comes to this rule too.
    /// 3. Else `nil`: the host's handler, or a cancel, answers.
    ///
    /// Two contexts are of one run when their `holdingRunToken` is the same.
    /// That token is the completion token of the run that holds the call,
    /// and each run gets a new one. The session id, the tool name and the op
    /// do not tell two runs apart, because two runs can share them. The
    /// `completionToken` of a context does not tell it either: each inner
    /// `tools.*` call of a `runCode` snippet has its own completion token,
    /// but the snippet runs each of them to completion, thus the `runCode`
    /// run holds each of them. Two inner calls of one snippet come to rule 2,
    /// and the question goes to the `runCode` run. A call that a run mounts
    /// in the background is a run of its own, with its own holding token.
    ///
    /// A server is linked to one of two calls from different runs only when
    /// it echoes the `progressToken` of the call in the `_meta` of
    /// `elicitation/create`. MCP gives no standard link otherwise: stdio has
    /// no wire link from a request to a request, and the swift-sdk does not
    /// use the link of the POST stream of streamable HTTP, because its server
    /// sends requests on the GET stream and its client merges the streams.
    ///
    /// - Parameter meta: The `_meta` of the `elicitation/create`, or `nil`.
    /// - Returns: The context, or `nil`.
    private func callingContext(linkedBy meta: Metadata?) -> ToolContext? {
        if let token = meta?.progressToken, let context = inFlightCalls[Self.requestID(of: token)]?.context {
            return context
        }
        return contextOfTheOneRunInFlight()
    }

    /// The context of the one run that made each call in flight, or `nil`
    /// when no call is in flight, when a call has no context, or when two
    /// calls are of different runs. Two contexts are of one run when their
    /// `holdingRunToken` is the same — see ``callingContext(linkedBy:)``.
    ///
    /// - Returns: The context, or `nil`.
    private func contextOfTheOneRunInFlight() -> ToolContext? {
        let contexts = inFlightCalls.values.map(\.context)
        guard let first = contexts.first, let context = first,
            contexts.allSatisfy({ $0?.holdingRunToken == context.holdingRunToken })
        else {
            return nil
        }
        return context
    }

    /// The cancel of a question that no context and no handler can answer,
    /// with the reason, after a log record.
    ///
    /// When two or more calls are in flight and one of them has a context,
    /// the question cannot be linked to one of them: the calls are from
    /// different runs, and the `_meta` named none. Else no call of a run is
    /// in flight, and the host has no handler.
    ///
    /// - Returns: The cancel.
    private func cancelWithNoAnswerer() -> ElicitationResponse {
        let callCount = inFlightCalls.count
        let metadata: Logger.Metadata = [MultitoolTelemetry.LogMetadataKey.itemCount.rawValue: "\(callCount)"]
        guard callCount > 1, inFlightCalls.values.contains(where: { $0.context != nil }) else {
            record(.mcpElicitationNoAnswerer, level: .warning, metadata: metadata)
            return .cancel(reason: Self.noAnswererReason)
        }
        record(.mcpElicitationNotLinked, level: .warning, metadata: metadata)
        return .cancel(reason: Self.notLinkedReason(callCount: callCount))
    }

    /// The reason of the cancel of a question that no run and no handler can
    /// answer.
    static let noAnswererReason = "no run and no host handler can answer the question"

    /// The reason of the cancel of a question that cannot be linked to one
    /// of the calls in flight.
    ///
    /// - Parameter callCount: The count of calls in flight.
    /// - Returns: The reason.
    static func notLinkedReason(callCount: Int) -> String {
        "the question cannot be linked to one tool call: \(callCount) calls in flight from different runs"
    }

    /// Adds the URL-mode question `request` of `context` to
    /// ``pendingContextElicitations`` under its wire id, before
    /// `context.elicit(_:)` posts the question. Thus a completion that the
    /// relay reads at any time after the post finds the entry.
    ///
    /// When an open question already uses `wireId`, this function does not
    /// change that entry, and writes a record.
    ///
    /// - Parameters:
    ///   - wireId: The wire `elicitationId` of the request.
    ///   - request: The decoded request. Its `elicitationId` is the id that
    ///     this actor chose.
    ///   - context: The context of the calling run.
    /// - Returns: `true` when this call added the entry, thus the caller
    ///   removes it when the question ends.
    private func openContextElicitation(
        _ wireId: String, request: ElicitationRequest, context: ToolContext
    ) -> Bool {
        guard pendingContextElicitations[wireId] == nil else {
            record(
                .mcpElicitationWireIdInUse, level: .warning,
                metadata: [MultitoolTelemetry.LogMetadataKey.elicitationID.rawValue: "\(wireId)"])
            return false
        }
        pendingContextElicitations[wireId] = (context, request.elicitationId, connectGeneration)
        return true
    }

    /// Suspends the calling run on `request` through `context` — case 1.
    /// `ToolContext.elicit(_:)` never throws today; a throw, should one ever
    /// come, answers `cancel` rather than an error into the transport.
    ///
    /// - Parameters:
    ///   - request: The decoded request.
    ///   - context: The context of the calling run.
    /// - Returns: The user's answer.
    private func elicit(_ request: ElicitationRequest, through context: ToolContext) async -> ElicitationResponse {
        do {
            return try await context.elicit(request)
        } catch {
            record(
                .mcpElicitationThroughRunFailed, level: .warning,
                metadata: MultitoolTelemetry.errorMetadata(of: error))
            return .cancel
        }
    }

    // MARK: - The URL flow under the handler

    /// Holds a URL-mode accept the handler gave until ``complete(elicitationId:)``
    /// names `elicitationId` — the third message of the flow, on the host's
    /// side. A second flow opened under an id that is still held resumes the
    /// earlier one, so no accept waits forever.
    ///
    /// - Parameter elicitationId: The wire id of the flow.
    private func awaitHostCompletion(of elicitationId: String) async {
        await withCheckedContinuation { continuation in
            if let earlier = pendingHostElicitations.removeValue(forKey: elicitationId) {
                earlier.resume()
            }
            pendingHostElicitations[elicitationId] = continuation
            resumeHostElicitationHeldWaiters(of: elicitationId)
        }
    }

    /// Waits until this actor holds the URL-mode flow named `elicitationId`
    /// — the event a test waits on in place of a poll of
    /// ``pendingHostElicitationIds``. Returns at once when the flow is
    /// already held.
    ///
    /// Internal, for `@testable import`: no product code waits here.
    ///
    /// - Parameter elicitationId: The wire id of the flow.
    func waitUntilHostElicitationHeld(elicitationId: String) async {
        guard pendingHostElicitations[elicitationId] == nil else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            hostElicitationHeldWaiters.append((elicitationId, continuation))
        }
    }

    /// Resumes each wait of ``waitUntilHostElicitationHeld(elicitationId:)``
    /// for `elicitationId`.
    ///
    /// - Parameter elicitationId: The wire id of the flow that is now held.
    private func resumeHostElicitationHeldWaiters(of elicitationId: String) {
        let held = hostElicitationHeldWaiters.filter { $0.elicitationId == elicitationId }
        hostElicitationHeldWaiters.removeAll { $0.elicitationId == elicitationId }
        for waiter in held {
            waiter.continuation.resume()
        }
    }

    /// Ends the URL-mode flow named `elicitationId`. The host calls this when
    /// the out-of-band interaction ends, and the relay of
    /// `notifications/elicitation/complete` calls it too.
    ///
    /// The order is the order of the header of this file: a held accept of
    /// the host's handler goes to the server; else an open question of a
    /// bound `ToolContext` of the current connect generation completes
    /// through that context; else the id is ignored, per the spec.
    ///
    /// - Parameter elicitationId: The wire id of the flow.
    public func complete(elicitationId: String) async {
        await complete(elicitationId: elicitationId, generation: connectGeneration)
    }

    /// Ends the URL-mode flow named `elicitationId` as
    /// ``complete(elicitationId:)`` does, for the connect attempt of
    /// `generation`. The relay of the `DropObservingTransport` of an attempt
    /// calls this with the generation of that attempt. Thus a completion
    /// that an old transport relays does not reach a question of a newer
    /// connection.
    ///
    /// - Parameters:
    ///   - elicitationId: The wire id of the flow.
    ///   - generation: The ``connectGeneration`` of the attempt that read
    ///     the completion.
    func complete(elicitationId: String, generation: Int) async {
        let metadata: Logger.Metadata = [
            MultitoolTelemetry.LogMetadataKey.elicitationID.rawValue: "\(elicitationId)"
        ]
        if let continuation = pendingHostElicitations.removeValue(forKey: elicitationId) {
            continuation.resume()
            return
        }
        guard let open = pendingContextElicitations[elicitationId], open.generation == generation else {
            record(.mcpElicitationCompletionIgnored, level: .debug, metadata: metadata)
            return
        }
        let delivery = await open.context.complete(elicitationId: open.id)
        record(
            .mcpElicitationCompletionRelayed, level: .debug,
            metadata: metadata.merging([
                MultitoolTelemetry.LogMetadataKey.elicitationCompletionDelivery.rawValue: "\(delivery)"
            ]) { wireId, _ in wireId })
    }

    /// The wire ids of the URL-mode flows the handler accepted and this actor
    /// still holds — what a test reads to know a flow is held.
    var pendingHostElicitationIds: [String] {
        Array(pendingHostElicitations.keys)
    }

    // MARK: - The wire shapes

    /// Decodes the wire `requestedSchema` into the restricted subset of
    /// FoundationModelsExtras, or logs why it stands outside it and returns
    /// `nil`.
    ///
    /// The wire schema is re-encoded as JSON and read by the decoder of
    /// `ElicitationRequestedSchema`, so this boundary enforces exactly the subset every other
    /// elicitor does.
    ///
    /// - Parameter schema: The schema the server sent.
    /// - Returns: The restricted schema, or `nil`.
    private func decodeRestrictedSchema(_ schema: Elicitation.RequestSchema) -> ElicitationRequestedSchema? {
        do {
            let encoded = try JSONEncoder().encode(schema)
            return try JSONDecoder().decode(ElicitationRequestedSchema.self, from: encoded)
        } catch {
            record(
                .mcpElicitationSchemaDeclined, level: .warning,
                metadata: MultitoolTelemetry.errorMetadata(of: error))
            return nil
        }
    }

    /// The key of the reason in the `_meta` of a decline or a cancel on the
    /// wire. It is the same key as `ACPClient.elicitationReasonMetaKey` of
    /// FoundationModelsACPClient, thus the two sides of an agent read one
    /// key.
    static let elicitationReasonMetaKey = "reason"

    /// Encodes an answer as the `CreateElicitation.Result` the server reads.
    ///
    /// A decline or a cancel that gives a reason carries it in `_meta`,
    /// under ``elicitationReasonMetaKey``. One with no reason has no `_meta`.
    ///
    /// - Parameter response: The answer.
    /// - Returns: The wire result.
    static func wireResult(of response: ElicitationResponse) -> CreateElicitation.Result {
        switch response.action {
        case .accept:
            return CreateElicitation.Result(
                action: .accept, content: response.content.map { $0.mapValues(wireValue) })
        case .decline:
            return CreateElicitation.Result(action: .decline, _meta: reasonMetadata(of: response))
        case .cancel:
            return CreateElicitation.Result(action: .cancel, _meta: reasonMetadata(of: response))
        }
    }

    /// The `_meta` that carries the reason of `response`.
    ///
    /// - Parameter response: A decline or a cancel.
    /// - Returns: The metadata with the reason under
    ///   ``elicitationReasonMetaKey``, or `nil` when `response` gives no
    ///   reason.
    private static func reasonMetadata(of response: ElicitationResponse) -> Metadata? {
        response.reason.map { Metadata(additionalFields: [elicitationReasonMetaKey: .string($0)]) }
    }

    /// One filled form value on the wire.
    ///
    /// - Parameter value: The answered value.
    /// - Returns: Its wire form.
    private static func wireValue(_ value: ElicitationValue) -> Value {
        switch value {
        case .string(let text):
            return .string(text)
        case .number(let number):
            return .double(number)
        case .boolean(let flag):
            return .bool(flag)
        case .stringArray(let texts):
            return .array(texts.map { .string($0) })
        }
    }
}
