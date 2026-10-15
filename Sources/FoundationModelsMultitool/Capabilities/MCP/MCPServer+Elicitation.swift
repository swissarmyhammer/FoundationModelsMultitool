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
//    records it in the in-flight table, and the request is attributed to the
//    sole call in flight, never a guess among several. `context.elicit(_:)`
//    suspends the run on the run plane of the session. The answer is not held.
// 2. Else the host's `elicitationHandler` — the bare-session path. Apple's
//    tool call holds the turn while the user answers: the ordinary cost of a
//    plain tool on a plain session.
// 3. Else `cancel` to the server. Never a throw into the transport.
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
// suspended after the accept until `RunPlane.complete(elicitationId:)`,
// so the accept reaches the wire only once the host has closed the flow.
// Under the handler, this actor holds the accept the same way until the host
// calls `complete(elicitationId:)`. The swift-sdk client runs a request
// handler inline in its message loop, so no wire message — the relayed
// `notifications/elicitation/complete` included — can arrive while the
// handler is held; a relayed completion therefore names either a flow the
// host has already closed, or an id this actor never opened, and both are
// ignored, per the spec. `complete(elicitationId:)` is the one end of a held
// flow, whether the host calls it or the relay does.

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
            return Self.wireResult(of: await resolve(request, urlElicitationId: nil))
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
            return Self.wireResult(of: await resolve(request, urlElicitationId: url.elicitationId))
        }
    }

    // MARK: - The resolution order

    /// Resolves `request` through the first answerer that stands: the
    /// calling run's context, else the host's handler, else `cancel`.
    ///
    /// - Parameters:
    ///   - request: The decoded request.
    ///   - urlElicitationId: The wire `elicitationId` of a URL-mode request,
    ///     which a held accept under the handler is keyed by; `nil` in form
    ///     mode.
    /// - Returns: The answer.
    private func resolve(_ request: ElicitationRequest, urlElicitationId: String?) async -> ElicitationResponse {
        if let context = callingContext() {
            return await elicit(request, through: context)
        }
        guard let elicitationHandler else {
            return .cancel
        }
        let response = await elicitationHandler(request)
        if let urlElicitationId, response.action == .accept {
            await awaitHostCompletion(of: urlElicitationId)
        }
        return response
    }

    /// The context of the one call in flight, when exactly one is and it was
    /// made under a context — the attribution rule of the source: a request
    /// is attributed to the sole call in flight, never to a guess among
    /// several, and a bare call carries no context to attribute to.
    ///
    /// - Returns: The context, or `nil`.
    private func callingContext() -> ToolContext? {
        guard inFlightCalls.count == 1, let entry = inFlightCalls.values.first else {
            return nil
        }
        return entry.context
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

    /// Ends the URL-mode flow named `elicitationId`: the accept the host's
    /// handler gave for it goes to the server. The host calls this when the
    /// out-of-band interaction ends, and the relay of
    /// `notifications/elicitation/complete` calls it too. An id this actor
    /// holds no flow for — never opened, already ended, or a flow a bound
    /// `ToolContext` answered, which `RunPlane.complete(elicitationId:)`
    /// ends instead — is ignored, per the spec.
    ///
    /// - Parameter elicitationId: The wire id of the flow.
    public func complete(elicitationId: String) {
        guard let continuation = pendingHostElicitations.removeValue(forKey: elicitationId) else {
            record(
                .mcpElicitationCompletionIgnored, level: .debug,
                metadata: [MultitoolTelemetry.LogMetadataKey.elicitationID.rawValue: "\(elicitationId)"])
            return
        }
        continuation.resume()
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
