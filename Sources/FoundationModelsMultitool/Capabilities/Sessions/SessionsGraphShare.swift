// The share of a session in the `sessions` GraphQL endpoint (D208 (k)): the
// `share` field of a session, the mutations `shareSession`,
// `updateSessionShare` and `stopSharingSession`, their types, and the sharer
// that the endpoint keeps.
//
// The field and the mutations call the share steps of `SessionsToolContext`,
// thus the tool ops and the mutations share one rule and one corrective, and
// the same codes: `SHARING_UNAVAILABLE`, `NOT_SHARED` and `SHARE_FAILED`.
// An external client shares, updates and stops only a session that it owns,
// as for the other changes of one session (session.md section 11.3).
//
// A change of a share is an event of the change feed of its session. The
// directory does not know about a share, so the endpoint keeps the sharer of
// the host inside a `SessionsGraphRecordingSharer`: each share, update and
// stop that succeeds records one `changed` entry of its session. The tool and
// the endpoint read the same recording sharer, so a tool op and a mutation
// each record the entry.

import Foundation
import FoundationModelsExtras
import Graphiti
import ULID

// MARK: - The recording sharer

/// The sharer that the `sessions` endpoint keeps: it calls the sharer of the
/// host, and records one `changed` entry of the session in the change log
/// after each share, update and stop that succeeds.
///
/// A call that fails records nothing, and a read of a share records nothing.
struct SessionsGraphRecordingSharer: SessionSharer {
    /// The sharer of the host.
    let base: any SessionSharer

    /// The recorder of the change log of the endpoint.
    let recorder: SessionsGraphChangeRecorder

    /// Shares the session with the sharer of the host, and records the
    /// change.
    ///
    /// - Parameters:
    ///   - session: The id of the session.
    ///   - options: The content and the state of the share.
    /// - Returns: The new share.
    /// - Throws: What the sharer of the host throws.
    func share(_ session: ULID, options: SessionShareOptions) async throws -> SessionShare {
        try await recordingChange(of: session) { try await base.share(session, options: options) }
    }

    /// Updates the share with the sharer of the host, and records the
    /// change.
    ///
    /// - Parameters:
    ///   - session: The id of the session.
    ///   - options: The options of the share after the update.
    /// - Returns: The updated share.
    /// - Throws: What the sharer of the host throws.
    func update(_ session: ULID, options: SessionShareOptions) async throws -> SessionShare {
        try await recordingChange(of: session) { try await base.update(session, options: options) }
    }

    /// Stops the share with the sharer of the host, and records the change.
    ///
    /// - Parameter session: The id of the session.
    /// - Throws: What the sharer of the host throws.
    func stop(_ session: ULID) async throws {
        try await recordingChange(of: session) { try await base.stop(session) }
    }

    /// The share of a session, from the sharer of the host.
    ///
    /// - Parameter session: The id of the session.
    /// - Returns: The share, or `nil` when the session has no share.
    /// - Throws: What the sharer of the host throws.
    func share(of session: ULID) async throws -> SessionShare? {
        try await base.share(of: session)
    }

    /// The share changes from outside of the sharer of the host.
    ///
    /// - Returns: The stream of the sharer of the host.
    func shareChanges() -> AsyncStream<ULID> {
        base.shareChanges()
    }

    /// Runs one change of a share, and records one `changed` entry of the
    /// session when the change succeeds.
    ///
    /// - Parameters:
    ///   - session: The session of the change.
    ///   - change: The call of the sharer of the host.
    /// - Returns: What `change` gave.
    /// - Throws: What `change` throws. Then the step records nothing.
    private func recordingChange<Value: Sendable>(
        of session: ULID, _ change: () async throws -> Value
    ) async throws -> Value {
        let value = try await change()
        await recorder.record(.changed, of: session)
        return value
    }
}

// MARK: - The types

/// The `SessionShare` type: the link and the state of the share of a
/// session, never its content.
struct SessionsGraphShare: Sendable {
    /// The link of the share.
    let url: String

    /// True when anyone with the link can open the share now.
    let anyoneWithLink: Bool

    /// The options of the share.
    let options: SessionShareOptions

    /// The time of the snapshot of the share.
    let updatedAt: DateTime

    /// Makes the type of a share.
    ///
    /// - Parameter share: The share that the sharer gave.
    init(_ share: SessionShare) {
        url = share.url.absoluteString
        anyoneWithLink = share.anyoneWithLink
        options = share.options
        updatedAt = DateTime(share.updatedAt)
    }
}

/// The `SessionShareOptionsInput` input object: the options of a new share.
/// Each option that a call does not give has its value of
/// ``SessionShareOptions/defaults``.
struct SessionsGraphShareOptionsInput: Codable, Sendable {
    /// True to put the thoughts of the agent in the share, or `nil`.
    let includeThoughts: Bool?

    /// True to put the output of the tool calls in the share, or `nil`.
    let includeToolOutput: Bool?

    /// True when anyone with the link can open the share, or `nil`.
    let anyoneWithLink: Bool?

    /// True to update the share at the end of each turn, or `nil`.
    let keepUpdated: Bool?

    /// The options of the share.
    var options: SessionShareOptions {
        SessionShareOptions(
            thoughts: includeThoughts, toolOutput: includeToolOutput, anyoneWithLink: anyoneWithLink,
            keepUpdated: keepUpdated)
    }
}

/// The input of `Mutation.shareSession`.
struct SessionsGraphShareInput: Codable, Sendable {
    /// The session to share: a reference, as the tool reads it.
    let id: ToolkitID

    /// The options of a new share, or `nil` for the defaults.
    let options: SessionsGraphShareOptionsInput?
}

/// The input of `Mutation.updateSessionShare`.
struct SessionsGraphUpdateShareInput: Codable, Sendable {
    /// The shared session: a reference, as the tool reads it.
    let id: ToolkitID

    /// The new value of the switch Keep Updated, or `nil` to keep it.
    let keepUpdated: Bool?
}

/// The input of `Mutation.stopSharingSession`.
struct SessionsGraphStopSharingInput: Codable, Sendable {
    /// The shared session: a reference, as the tool reads it.
    let id: ToolkitID
}

// MARK: - The resolvers

extension SessionsGraphSession {
    /// Resolves `Session.share`: the share of this session from the sharer
    /// of the endpoint, or `nil` when the session has no share.
    ///
    /// - Parameters:
    ///   - context: The context of the call, which gives the sharer.
    ///   - arguments: No argument.
    /// - Returns: The share, or `nil`.
    /// - Throws: ``SessionsRefusal`` with the code `SHARING_UNAVAILABLE` when
    ///   the endpoint has no sharer, or `SHARE_FAILED` when the sharer fails;
    ///   each with the corrective of the share operations.
    func share(context: SessionsGraphContext, arguments _: NoArguments) async throws -> SessionsGraphShare? {
        let sharer = try SessionsToolContext.requiredSharer(context.sharer)
        return try await SessionsToolContext.existingShare(of: sessionID, from: sharer).map(SessionsGraphShare.init)
    }
}

extension SessionsGraphResolver {
    /// Resolves `Mutation.shareSession`: shares a session that the viewer
    /// owns. A session with a share keeps it.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The input object.
    /// - Returns: The session, whose `share` gives the share.
    /// - Throws: The coded error of a refusal, and each other error of the
    ///   directory.
    func shareSession(
        context: SessionsGraphContext, arguments: SessionsGraphMutationArguments<SessionsGraphShareInput>
    ) async throws -> SessionsGraphSession {
        let input = arguments.input
        return try await Self.shareChange(of: .share, on: input.id, in: context) { target, sharer in
            _ = try await SessionsToolContext.share(target, options: input.options?.options ?? .defaults, with: sharer)
        }
    }

    /// Resolves `Mutation.updateSessionShare`: replaces the snapshot of the
    /// share of a session that the viewer owns, and can change its switch
    /// Keep Updated.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The input object.
    /// - Returns: The session, whose `share` gives the updated share.
    /// - Throws: The coded error of a refusal, and each other error of the
    ///   directory.
    func updateSessionShare(
        context: SessionsGraphContext, arguments: SessionsGraphMutationArguments<SessionsGraphUpdateShareInput>
    ) async throws -> SessionsGraphSession {
        let input = arguments.input
        return try await Self.shareChange(of: .updateShare, on: input.id, in: context) { target, sharer in
            _ = try await SessionsToolContext.updateShare(of: target, keepUpdated: input.keepUpdated, with: sharer)
        }
    }

    /// Resolves `Mutation.stopSharingSession`: stops the share of a session
    /// that the viewer owns.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The input object.
    /// - Returns: The session, whose `share` is `null`.
    /// - Throws: The coded error of a refusal, and each other error of the
    ///   directory.
    func stopSharingSession(
        context: SessionsGraphContext, arguments: SessionsGraphMutationArguments<SessionsGraphStopSharingInput>
    ) async throws -> SessionsGraphSession {
        try await Self.shareChange(of: .stopSharing, on: arguments.input.id, in: context) { target, sharer in
            try await SessionsToolContext.stopSharing(target, with: sharer)
        }
    }

    /// Runs the change of a share mutation on the session of an id argument,
    /// which the viewer must own (section 11.3). The actor comes first, as
    /// for a fork, then the sharer, as in the tool op, then the session.
    ///
    /// - Parameters:
    ///   - mutation: The mutation, for the corrective of a call with no
    ///     caller session.
    ///   - id: The id argument.
    ///   - context: The context of the call.
    ///   - change: The share step, given the session id and the sharer.
    /// - Returns: The session.
    /// - Throws: The coded error of a refusal, and each other error of the
    ///   directory.
    private static func shareChange(
        of mutation: SessionsGraphMutation, on id: ToolkitID, in context: SessionsGraphContext,
        _ change: (ULID, any SessionSharer) async throws -> Void
    ) async throws -> SessionsGraphSession {
        try await coding {
            _ = try context.actor(of: mutation)
            let sharer = try SessionsToolContext.requiredSharer(context.sharer)
            let summary = try await context.ownedSummary(try await context.referencedSession(id))
            try await change(summary.id, sharer)
            return SessionsGraphSession(summary)
        }
    }
}

// MARK: - The schema

extension SessionsGraphAPI {
    /// The text of the description of the `id` of a share input.
    private static let shareIDDescription =
        "The session: its id in any letter case or its short id, with or without @, or @ and its slug. An id of a "
        + "session that you cannot see, or a session that an external client does not own, is NOT_FOUND."

    /// The text of the rule of each share mutation with no sharer.
    private static let noSharerRule = "SHARING_UNAVAILABLE when this server cannot share a session."

    /// The `SessionShareOptions` type.
    ///
    /// - Returns: The type.
    static func shareOptionsType() -> SchemaType {
        Type(SessionShareOptions.self, as: "SessionShareOptions") {
            Field("includeThoughts", at: \.includeThoughts).description("True when the share has the thoughts.")
            Field("includeToolOutput", at: \.includeToolOutput)
                .description("True when the share has the output of the tool calls.")
            Field("anyoneWithLink", at: \.anyoneWithLink)
                .description("True when the share was made for anyone with the link.")
            Field("keepUpdated", at: \.keepUpdated)
                .description("True when the server updates the share at the end of each turn.")
        }
        .description("The content and the state of the share of a session.")
    }

    /// The `SessionShare` type.
    ///
    /// - Returns: The type.
    static func shareType() -> SchemaType {
        Type(SessionsGraphShare.self, as: "SessionShare") {
            Field("url", at: \.url).description("The link of the share.")
            Field("anyoneWithLink", at: \.anyoneWithLink)
                .description(
                    "True when anyone with the link can open the share now. False when only the invited people can.")
            Field("options", at: \.options).description("The options of the share.")
            Field("updatedAt", at: \.updatedAt).description("The time of the snapshot of the share.")
        }
        .description("The link and the state of the share of a session over iCloud sharing, never its content.")
    }

    /// The `SessionShareOptionsInput` input object.
    ///
    /// - Returns: The input object.
    static func shareOptionsInput() -> SchemaType {
        let defaults = SessionShareOptions.defaults
        return Input(SessionsGraphShareOptionsInput.self, as: SessionsGraphMutation.shareOptionsInputName) {
            InputField("includeThoughts", at: \.includeThoughts)
                .defaultValue(defaults.includeThoughts)
                .description("True to put the thoughts of the agent in the share.")
            InputField("includeToolOutput", at: \.includeToolOutput)
                .defaultValue(defaults.includeToolOutput)
                .description("True to put the output of the tool calls in the share.")
            InputField("anyoneWithLink", at: \.anyoneWithLink)
                .defaultValue(defaults.anyoneWithLink)
                .description("True when anyone with the link can open the share. False: only the invited people.")
            InputField("keepUpdated", at: \.keepUpdated)
                .defaultValue(defaults.keepUpdated)
                .description("True to update the share at the end of each turn. False: the share does not change.")
        }
        .description("The options of a new share. Each option that you do not give has its default.")
    }

    /// The `ShareSessionInput` input object.
    ///
    /// - Returns: The input object.
    static func shareInput() -> SchemaType {
        Input(SessionsGraphShareInput.self, as: SessionsGraphMutation.share.inputName) {
            InputField("id", at: \.id).description(shareIDDescription)
            InputField("options", at: \.options).description("The options of a new share. None: the defaults.")
        }
        .description("The session to share, and the options of a new share.")
    }

    /// The `UpdateSessionShareInput` input object.
    ///
    /// - Returns: The input object.
    static func updateShareInput() -> SchemaType {
        Input(SessionsGraphUpdateShareInput.self, as: SessionsGraphMutation.updateShare.inputName) {
            InputField("id", at: \.id).description(shareIDDescription)
            InputField("keepUpdated", at: \.keepUpdated)
                .description("True to update the share at the end of each turn, false to stop that. None: no change.")
        }
        .description("The shared session to update, and the new value of its switch Keep Updated.")
    }

    /// The `StopSharingSessionInput` input object.
    ///
    /// - Returns: The input object.
    static func stopSharingInput() -> SchemaType {
        Input(SessionsGraphStopSharingInput.self, as: SessionsGraphMutation.stopSharing.inputName) {
            InputField("id", at: \.id).description(shareIDDescription)
        }
        .description("The shared session whose share to stop.")
    }

    /// The fields of the share mutations, in the order of
    /// ``SessionsGraphMutation/all``.
    ///
    /// - Returns: The fields.
    static func shareMutationFields() -> [SchemaField] {
        [
            mutationField(
                .share, at: SessionsGraphResolver.shareSession, input: "The session and the options of a new share.",
                description: "Shares a session as a read-only link over iCloud sharing. A session that has a share "
                    + "keeps it. Gives the session: its share gives the link and the state, not the content. "
                    + noSharerRule),
            mutationField(
                .updateShare, at: SessionsGraphResolver.updateSessionShare,
                input: "The shared session and its switch Keep Updated.",
                description: "Updates the share of a session with the session now. The link does not change. A "
                    + "session with no share gives NOT_SHARED. Gives the session. \(noSharerRule)"),
            mutationField(
                .stopSharing, at: SessionsGraphResolver.stopSharingSession, input: "The shared session.",
                description: "Stops the share of a session: its link then opens nothing. Copies that people saved "
                    + "stay. A session with no share gives NOT_SHARED. Gives the session. \(noSharerRule)"),
        ]
    }
}
