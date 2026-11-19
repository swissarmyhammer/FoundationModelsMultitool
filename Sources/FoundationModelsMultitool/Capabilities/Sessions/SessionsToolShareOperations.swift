// The `share session`, `update share` and `stop sharing` operations of the
// `sessions` tool (D208 (k), D100: the agent can do what the UI can do).
//
// `share session` shares a session as a read-only link, `update share`
// replaces the snapshot of the share and can change its switch Keep Updated,
// and `stop sharing` stops the share. Each answer gives the URL and the state
// of the share, never the content. The host gives the share through a
// ``SessionSharer``. With no sharer, each operation gives the corrective of
// the code `SHARING_UNAVAILABLE`.
//
// The `id` takes each form of the one resolver of D199 (d), and the default
// is the caller session: each operation acts for the caller session, as the
// export does. The operations ask for no extra approval (Q80): they run under
// the normal permission rules (D3). Each error is a corrective text, never a
// thrown model error.
//
// The share steps are static functions of ``SessionsToolContext``, so the
// mutations of the `sessions` endpoint use the same steps and the same
// correctives.

import Foundation
import FoundationModels
import FoundationModelsExtras
import Operations
import ULID

/// What a share operation did to the share of a session, for the first
/// sentence of its answer.
enum SessionShareChange: Sendable, Equatable {
    /// `share session` made a new share.
    case new

    /// `share session` found a share of the session, and changed nothing.
    case existing

    /// `update share` replaced the snapshot of the share.
    case updated
}

/// The share that `share session` gives, and whether it is new.
struct SessionShareOutcome: Sendable, Equatable {
    /// The share of the session.
    let share: SessionShare

    /// ``SessionShareChange/new`` for a new share, or
    /// ``SessionShareChange/existing`` for the share that the session had.
    let change: SessionShareChange
}

/// Shares a session as a read-only link (`share session`).
@Generable
@Operation(
    verb: "share", noun: "session",
    description: """
        Share a session as a read-only link over iCloud sharing. Gives the link and the state of the share, not \
        the content. A session that has a share already gives its share, with no change.
        """)
struct ShareSession {
    /// The session to share: its id, its short id or its slug.
    @Guide(description: SessionsToolText.optionalSessionReference)
    @OperationParam(aliases: ["sessionId", "session"])
    var id: String?

    /// True to put the thoughts of the agent in the share.
    @Guide(description: "Optional. True to put the thoughts of the agent in the share. The default is true.")
    @OperationParam(aliases: ["includeThoughts"])
    var thoughts: Bool?

    /// True to put the output of the tool calls in the share.
    @Guide(description: "Optional. True to put the output of the tool calls in the share. The default is true.")
    @OperationParam(aliases: ["includeToolOutput"])
    var toolOutput: Bool?

    /// True when anyone with the link can open the share.
    @Guide(
        description: """
            Optional. True when anyone with the link can open the share. False when only the people that the user \
            invites can open it. The default is true.
            """)
    @OperationParam(aliases: ["anyone", "public"])
    var anyoneWithLink: Bool?

    /// True to update the share at the end of each turn.
    @Guide(
        description: """
            Optional. True to update the share at the end of each turn of the session. The default is false: the \
            share does not change until update share.
            """)
    @OperationParam(aliases: ["live", "autoUpdate"])
    var keepUpdated: Bool?
}

extension ShareSession {
    /// Shares the session `id`, or the caller session.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: The link and the state of the share. A corrective for a
    ///   call with no caller, a server with no sharer, an id that names no
    ///   session that the caller can see, and a sharer that fails.
    func execute(in context: SessionsToolContext) async throws -> String {
        await context.answer(asCallerOf: Self.opString) { callerID in
            let sharer = try SessionsToolContext.requiredSharer(context.sharer)
            let target = try await context.sessionID(referencedBy: id, defaultingTo: callerID)
            let options = SessionShareOptions(
                thoughts: thoughts, toolOutput: toolOutput, anyoneWithLink: anyoneWithLink, keepUpdated: keepUpdated)
            let outcome = try await SessionsToolContext.share(target, options: options, with: sharer)
            return SessionsToolText.shareAnswer(outcome.share, of: target, change: outcome.change)
        }
    }
}

/// Replaces the snapshot of the share of a session (`update share`).
@Generable
@Operation(
    verb: "update", noun: "share",
    description: """
        Update the share of a session with the session now, and change its switch Keep Updated. The link does not \
        change. Gives the link and the state of the share, not the content.
        """)
struct UpdateShare {
    /// The shared session: its id, its short id or its slug.
    @Guide(description: SessionsToolText.optionalSessionReference)
    @OperationParam(aliases: ["sessionId", "session"])
    var id: String?

    /// The new value of the switch Keep Updated.
    @Guide(
        description: """
            Optional. True to update the share at the end of each turn, false to stop that. The default keeps the \
            switch as it is.
            """)
    @OperationParam(aliases: ["live", "autoUpdate"])
    var keepUpdated: Bool?
}

extension UpdateShare {
    /// Updates the share of the session `id`, or of the caller session.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: The link and the state of the share. A corrective for a
    ///   call with no caller, a server with no sharer, an id that names no
    ///   session that the caller can see, a session with no share, and a
    ///   sharer that fails.
    func execute(in context: SessionsToolContext) async throws -> String {
        await context.answer(asCallerOf: Self.opString) { callerID in
            let sharer = try SessionsToolContext.requiredSharer(context.sharer)
            let target = try await context.sessionID(referencedBy: id, defaultingTo: callerID)
            let share = try await SessionsToolContext.updateShare(of: target, keepUpdated: keepUpdated, with: sharer)
            return SessionsToolText.shareAnswer(share, of: target, change: .updated)
        }
    }
}

/// Stops the share of a session (`stop sharing`).
@Generable
@Operation(
    verb: "stop", noun: "sharing",
    description: """
        Stop the share of a session: its link then opens nothing. Copies that people saved stay.
        """)
struct StopSharing {
    /// The shared session: its id, its short id or its slug.
    @Guide(description: SessionsToolText.optionalSessionReference)
    @OperationParam(aliases: ["sessionId", "session"])
    var id: String?
}

extension StopSharing {
    /// Stops the share of the session `id`, or of the caller session.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: The line that the share stopped. A corrective for a call
    ///   with no caller, a server with no sharer, an id that names no session
    ///   that the caller can see, a session with no share, and a sharer that
    ///   fails.
    func execute(in context: SessionsToolContext) async throws -> String {
        await context.answer(asCallerOf: Self.opString) { callerID in
            let sharer = try SessionsToolContext.requiredSharer(context.sharer)
            let target = try await context.sessionID(referencedBy: id, defaultingTo: callerID)
            try await SessionsToolContext.stopSharing(target, with: sharer)
            return SessionsToolText.sharingStopped(target)
        }
    }
}

extension SessionShareOptions {
    /// The options of a share call: each option that the call gives, and
    /// ``defaults`` for each option that it does not give.
    ///
    /// - Parameters:
    ///   - thoughts: True to put the thoughts in the share, or `nil`.
    ///   - toolOutput: True to put the tool output in the share, or `nil`.
    ///   - anyoneWithLink: True when anyone with the link can open the share,
    ///     or `nil`.
    ///   - keepUpdated: True to update the share at the end of each turn, or
    ///     `nil`.
    init(thoughts: Bool?, toolOutput: Bool?, anyoneWithLink: Bool?, keepUpdated: Bool?) {
        let defaults = Self.defaults
        self.init(
            includeThoughts: thoughts ?? defaults.includeThoughts,
            includeToolOutput: toolOutput ?? defaults.includeToolOutput,
            anyoneWithLink: anyoneWithLink ?? defaults.anyoneWithLink,
            keepUpdated: keepUpdated ?? defaults.keepUpdated)
    }
}

extension SessionsToolContext {
    /// The sharer of the host, for a share call.
    ///
    /// The share operations and the share mutations of the `sessions`
    /// endpoint refuse a call with no sharer with this one refusal.
    ///
    /// - Parameter sharer: The sharer of the host, or `nil`.
    /// - Returns: The sharer.
    /// - Throws: ``SessionsRefusal`` with the code `SHARING_UNAVAILABLE` when
    ///   `sharer` is `nil`.
    static func requiredSharer(_ sharer: (any SessionSharer)?) throws(SessionsRefusal) -> any SessionSharer {
        guard let sharer else {
            throw SessionsRefusal(.sharingUnavailable, SessionsToolText.noSharer)
        }
        return sharer
    }

    /// Shares a session: the one share step of `share session` and of the
    /// `shareSession` mutation. A session that has a share keeps it, and
    /// the step gives that share with no call to the sharer.
    ///
    /// - Parameters:
    ///   - target: The session.
    ///   - options: The options of a new share.
    ///   - sharer: The sharer of the host.
    /// - Returns: The share, and whether it is new.
    /// - Throws: ``SessionsRefusal`` with the code `SHARE_FAILED` when the
    ///   sharer fails.
    static func share(
        _ target: ULID, options: SessionShareOptions, with sharer: any SessionSharer
    ) async throws(SessionsRefusal) -> SessionShareOutcome {
        if let existing = try await existingShare(of: target, from: sharer) {
            return SessionShareOutcome(share: existing, change: .existing)
        }
        let share = try await sharerResult(for: target) { try await sharer.share(target, options: options) }
        return SessionShareOutcome(share: share, change: .new)
    }

    /// Replaces the snapshot of the share of a session: the one update step
    /// of `update share` and of the `updateSessionShare` mutation. The
    /// update keeps the options of the share, with the switch Keep Updated
    /// that the call gives.
    ///
    /// - Parameters:
    ///   - target: The session.
    ///   - keepUpdated: The new value of the switch Keep Updated, or `nil` to
    ///     keep it.
    ///   - sharer: The sharer of the host.
    /// - Returns: The updated share.
    /// - Throws: ``SessionsRefusal`` with the code `NOT_SHARED` when the
    ///   session has no share, or `SHARE_FAILED` when the sharer fails.
    static func updateShare(
        of target: ULID, keepUpdated: Bool?, with sharer: any SessionSharer
    ) async throws(SessionsRefusal) -> SessionShare {
        var options = try await requiredShare(of: target, from: sharer).options
        options.keepUpdated = keepUpdated ?? options.keepUpdated
        return try await sharerResult(for: target) { [options] in try await sharer.update(target, options: options) }
    }

    /// Stops the share of a session: the one stop step of `stop sharing`
    /// and of the `stopSharingSession` mutation.
    ///
    /// - Parameters:
    ///   - target: The session.
    ///   - sharer: The sharer of the host.
    /// - Throws: ``SessionsRefusal`` with the code `NOT_SHARED` when the
    ///   session has no share, or `SHARE_FAILED` when the sharer fails.
    static func stopSharing(_ target: ULID, with sharer: any SessionSharer) async throws(SessionsRefusal) {
        _ = try await requiredShare(of: target, from: sharer)
        try await sharerResult(for: target) { try await sharer.stop(target) }
    }

    /// The share of a session, which must exist.
    ///
    /// - Parameters:
    ///   - target: The session.
    ///   - sharer: The sharer of the host.
    /// - Returns: The share.
    /// - Throws: ``SessionsRefusal`` with the code `NOT_SHARED` when the
    ///   session has no share, or `SHARE_FAILED` when the sharer fails.
    private static func requiredShare(
        of target: ULID, from sharer: any SessionSharer
    ) async throws(SessionsRefusal) -> SessionShare {
        guard let share = try await existingShare(of: target, from: sharer) else {
            throw SessionsRefusal(.notShared, SessionsToolText.notShared(target))
        }
        return share
    }

    /// The share of a session, if it has one: the one read of the share
    /// steps, and of the `share` field of a session of the `sessions`
    /// endpoint.
    ///
    /// - Parameters:
    ///   - target: The session.
    ///   - sharer: The sharer of the host.
    /// - Returns: The share, or `nil`.
    /// - Throws: ``SessionsRefusal`` with the code `SHARE_FAILED` when the
    ///   sharer fails.
    static func existingShare(
        of target: ULID, from sharer: any SessionSharer
    ) async throws(SessionsRefusal) -> SessionShare? {
        try await sharerResult(for: target) { try await sharer.share(of: target) }
    }

    /// The result of one call of the sharer. Each error of the sharer
    /// becomes the one refusal of a failed share.
    ///
    /// - Parameters:
    ///   - target: The session of the call.
    ///   - call: The call of the sharer.
    /// - Returns: What `call` gave.
    /// - Throws: ``SessionsRefusal`` with the code `SHARE_FAILED` when
    ///   `call` throws.
    private static func sharerResult<Value: Sendable>(
        for target: ULID, _ call: () async throws -> Value
    ) async throws(SessionsRefusal) -> Value {
        do {
            return try await call()
        } catch {
            throw SessionsRefusal(.shareFailed, SessionsToolText.shareFailed(target, error: error))
        }
    }
}
