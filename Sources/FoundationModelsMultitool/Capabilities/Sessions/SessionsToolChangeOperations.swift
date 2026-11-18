// The change operations of the `sessions` tool: `start session`,
// `tag session`, `untag session`, `rename session`, `pin session`,
// `unpin session`, `archive session` and `unarchive session` (session.md
// section 8, D68, D72, D90, D100, D118, D204).
//
// Each operation acts for the caller session: a call with no caller gives a
// corrective, as section 8.2 says. Each answer is plain text, and each error
// is a corrective text, never a thrown model error:
// ``SessionsToolContext/answer(asCallerOf:_:)`` catches each error and gives
// ``SessionsToolText/corrective(for:)``. A `noLauncher` error of the directory
// is such a corrective, and so are the archive of a session that is archived
// already and the unarchive of a session that is not archived.
//
// The work of each change is in the extension of ``SessionsToolContext`` at
// the end of this file, which the mutations of the `sessions` endpoint call
// too (MT-10): the tool op and its mutation change the directory the same
// way, and refuse a call with the same corrective.
//
// TODO(MT-7): declare the risk facts of session.md section 8.3 on each
// operation (`tag session` and `untag session` change local facts,
// `start session` delegates work, `archive session` stops the turn of a
// session and hides it), when MT-1 and MT-7 land.

import Foundation
import FoundationModels
import FoundationModelsExtras
import Operations
import ULID

/// Starts a new root session of an agent (`start session`).
@Generable
@Operation(
    verb: "start", noun: "session",
    description: """
        Start a new root session of an agent with a first message. It works in the background, and its reply \
        comes to you as a message. The user sees it in the Sessions window; no tab opens.
        """)
struct StartSession {
    /// The agent id of the new session.
    @Guide(
        description: """
            Optional. The agent id. Use findAgents of the agents tool to get one; default is the default agent. \
            With no agent, the AGENT.md of the folder, else the default agent.
            """)
    @OperationParam(aliases: ["agentId"])
    var agent: String?

    /// The working folder of the new session.
    @Guide(description: "Optional. The absolute path of an existing folder. ~ expands. The default is your folder.")
    @OperationParam(aliases: ["folder"])
    var cwd: String?

    /// The first message of the new session.
    @Guide(description: "The first message. The new agent sees only this text.")
    @OperationParam(aliases: ["firstMessage", "prompt", "text"])
    var message: String

    /// The tags of the new session.
    @Guide(description: "Optional. The tags of the new session.")
    var tags: [String]?

    /// The title of the new session.
    @Guide(description: "Optional. The title of the new session.")
    @OperationParam(aliases: ["name"])
    var title: String?
}

extension StartSession {
    /// Starts the session, started by the caller, with the origin `tool`. A
    /// start by a model opens no tab (D90).
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: The new session, its agent and its folder. A corrective for
    ///   a call with no caller, a relative `cwd`, a blank `message`, a server
    ///   with no launcher, an unknown agent, or another error of the
    ///   directory.
    func execute(in context: SessionsToolContext) async throws -> String {
        await context.answer(asCallerOf: Self.opString) { callerID in
            let arguments = SessionStartArguments(agentId: agent, cwd: cwd, message: message, tags: tags, title: title)
            return SessionsToolText.started(try await context.start(with: arguments, by: .session(callerID)))
        }
    }
}

/// The text arguments of a start: the arguments of `start session`, and the
/// `StartSessionInput` of the `startSession` mutation.
struct SessionStartArguments: Codable, Sendable {
    /// The agent id, as it is written, or `nil` for the default agent.
    let agentId: String?

    /// The working folder, or `nil` for the folder of the session that
    /// starts it.
    let cwd: String?

    /// The first message.
    let message: String

    /// The tags, or `nil` for none.
    let tags: [String]?

    /// The title, or `nil` for none.
    let title: String?

    /// The start request of these arguments, for the session or the user
    /// that starts the session.
    ///
    /// A session starts a session of the origin `tool`, which no client
    /// opens in a tab. A user starts a session of the origin `client` on its
    /// client, which only that client opens in a tab (session.md section
    /// 11.5, D90).
    ///
    /// - Parameter starter: The session or the user that starts the session.
    /// - Returns: The request.
    /// - Throws: ``SessionsRefusal`` for an argument that the tool cannot
    ///   read.
    func request(by starter: SessionMessageSender) throws(SessionsRefusal) -> SessionStartRequest {
        var request = SessionStartRequest(
            agentID: SessionsToolInput.agentID(agentId),
            workingDirectory: try SessionsToolInput.folder(cwd),
            firstMessage: try SessionsToolInput.requiredText(message, parameter: SessionsToolText.messageParameter),
            tags: SessionsToolInput.tagSet(tags),
            title: SessionsToolInput.nonBlank(title),
            origin: .tool)
        switch starter {
        case .session(let sessionID):
            request.startedBy = sessionID
        case .user(let clientID):
            request.requestedByClient = clientID
            request.origin = .client
        }
        return request
    }
}

/// Adds tags to a session (`tag session`).
@Generable
@Operation(
    verb: "tag", noun: "session",
    description: "Add tags to a session. Gives the tags that the session has after the call.")
struct TagSession {
    /// The session to tag: its id, its short id or its slug.
    @Guide(description: SessionsToolText.optionalSessionReference)
    var id: String?

    /// The tags to add.
    @Guide(description: "The tags to add. Each tag has 1 to 64 characters: letters, digits, -, _, : and .")
    var tags: [String]
}

extension TagSession {
    /// Adds the tags to the session `id`, or to the caller session.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: The tags of the session after the call, or a corrective.
    func execute(in context: SessionsToolContext) async throws -> String {
        await context.answerTagChange(of: id, opString: Self.opString) { target in
            try await context.addTags(named: tags, to: target)
        }
    }
}

/// Removes tags from a session (`untag session`).
@Generable
@Operation(
    verb: "untag", noun: "session",
    description: "Remove tags from a session. Gives the tags that the session has after the call.")
struct UntagSession {
    /// The session to untag: its id, its short id or its slug.
    @Guide(description: SessionsToolText.optionalSessionReference)
    var id: String?

    /// The tags to remove.
    @Guide(description: "The tags to remove.")
    var tags: [String]
}

extension UntagSession {
    /// Removes the tags from the session `id`, or from the caller session.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: The tags of the session after the call, or a corrective.
    func execute(in context: SessionsToolContext) async throws -> String {
        await context.answerTagChange(of: id, opString: Self.opString) { target in
            try await context.removeTags(named: tags, from: target)
        }
    }
}

/// Sets the title of a session (`rename session`, D100: the agent can do
/// what the UI can).
@Generable
@Operation(verb: "rename", noun: "session", description: "Set the title of a session.")
struct RenameSession {
    /// The session to rename: its id, its short id or its slug.
    @Guide(description: SessionsToolText.optionalSessionReference)
    var id: String?

    /// The new title.
    @Guide(description: "The new title.")
    @OperationParam(aliases: ["name"])
    var title: String
}

extension RenameSession {
    /// Sets the title of the session `id`, or of the caller session.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: The new title of the session. A corrective for a call with
    ///   no caller, a blank title, an id that names no session or more than
    ///   one session, or another error of the directory.
    func execute(in context: SessionsToolContext) async throws -> String {
        await context.answer(asCallerOf: Self.opString) { callerID in
            let target = try await context.sessionID(referencedBy: id, defaultingTo: callerID)
            return SessionsToolText.renamed(try await context.rename(session: target, to: title))
        }
    }
}

/// Pins a session to the Pinned list of this server (`pin session`, D118,
/// D100 (a): the agent can pin too).
@Generable
@Operation(
    verb: "pin", noun: "session",
    description: """
        Pin a session: it shows in the Pinned list of the user on this Mac. A second pin keeps its place.
        """)
struct PinSession {
    /// The session to pin: its id, its short id or its slug.
    @Guide(description: SessionsToolText.optionalSessionReference)
    var id: String?
}

extension PinSession {
    /// Pins the session `id`, or the caller session.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: The pin state of the session after the call, or a
    ///   corrective.
    func execute(in context: SessionsToolContext) async throws -> String {
        await context.answerPinChange(of: id, to: true, opString: Self.opString)
    }
}

/// Removes a session from the Pinned list of this server (`unpin session`,
/// D118, D100 (a)).
@Generable
@Operation(
    verb: "unpin", noun: "session",
    description: "Unpin a session: it goes out of the Pinned list of the user on this Mac.")
struct UnpinSession {
    /// The session to unpin: its id, its short id or its slug.
    @Guide(description: SessionsToolText.optionalSessionReference)
    var id: String?
}

extension UnpinSession {
    /// Unpins the session `id`, or the caller session.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: The pin state of the session after the call, or a
    ///   corrective.
    func execute(in context: SessionsToolContext) async throws -> String {
        await context.answerPinChange(of: id, to: false, opString: Self.opString)
    }
}

/// Hides a session from the lists (`archive session`, D68, D72, D204).
@Generable
@Operation(
    verb: "archive", noun: "session",
    description: """
        Archive a session: stop its turn and hide it from the lists. It is not deleted: its transcript and its \
        inbox stay, and `unarchive session` brings it back.
        """)
struct ArchiveSession {
    /// The session to archive: its id, its short id or its slug.
    @Guide(description: SessionsToolText.archivedSessionReference)
    var id: String
}

extension ArchiveSession {
    /// Archives the session `id`, for the caller session.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: The session, its agent, its folder and the archive
    ///   sentence. A corrective for a call with no caller, a session that is
    ///   archived already, an id that names no session or more than one
    ///   session, or another error of the directory.
    func execute(in context: SessionsToolContext) async throws -> String {
        await context.answerArchiveChange(of: id, opString: Self.opString, scope: .unarchived) {
            SessionsToolText.archived(try await context.archive(session: $0, by: $1))
        }
    }
}

/// Shows an archived session in the lists again (`unarchive session`,
/// D204 (c)).
@Generable
@Operation(
    verb: "unarchive", noun: "session",
    description: """
        Unarchive a session: show it again in the lists. It stays a recorded session until a client opens it. \
        Its transcript and its inbox are as they were.
        """)
struct UnarchiveSession {
    /// The archived session: its id, or its short id or its slug, which
    /// name only an archived session.
    @Guide(description: SessionsToolText.unarchivedSessionReference)
    var id: String
}

extension UnarchiveSession {
    /// Unarchives the session `id`, for the caller session. A short id and
    /// a slug of the `id` match only the archived sessions, first in the
    /// folder of the caller, then in all the sessions.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: The session, its agent, its folder and the unarchive
    ///   sentence. A corrective for a call with no caller, a session that is
    ///   not archived, an id that names no archived session or more than one
    ///   archived session, or another error of the directory.
    func execute(in context: SessionsToolContext) async throws -> String {
        await context.answerArchiveChange(of: id, opString: Self.opString, scope: .archived) {
            SessionsToolText.unarchived(try await context.unarchive(session: $0, by: $1))
        }
    }
}

extension SessionsToolContext {
    /// Starts a new root session, for `start session` and the `startSession`
    /// mutation.
    ///
    /// - Parameters:
    ///   - arguments: The text arguments of the start.
    ///   - starter: The session or the user that starts the session.
    /// - Returns: The new session.
    /// - Throws: ``SessionsRefusal`` for an argument that the tool cannot
    ///   read, and each error of `SessionDirectory.start(_:)`.
    func start(with arguments: SessionStartArguments, by starter: SessionMessageSender) async throws -> SessionSummary {
        try await directory.start(try arguments.request(by: starter))
    }

    /// Adds tags to a session, for `tag session` and the `tagSession`
    /// mutation.
    ///
    /// - Parameters:
    ///   - texts: The tags of the call.
    ///   - target: The session.
    /// - Returns: The session after the call.
    /// - Throws: ``SessionsRefusal`` for a call with no tag, and each error
    ///   of `SessionDirectory.addTags(_:to:)`.
    func addTags(named texts: [String], to target: ULID) async throws -> SessionSummary {
        try await directory.addTags(try SessionsToolInput.tags(texts), to: target)
    }

    /// Removes tags from a session, for `untag session` and the
    /// `untagSession` mutation.
    ///
    /// - Parameters:
    ///   - texts: The tags of the call.
    ///   - target: The session.
    /// - Returns: The session after the call.
    /// - Throws: ``SessionsRefusal`` for a call with no tag, and each error
    ///   of `SessionDirectory.removeTags(_:from:)`.
    func removeTags(named texts: [String], from target: ULID) async throws -> SessionSummary {
        try await directory.removeTags(try SessionsToolInput.tags(texts), from: target)
    }

    /// Sets the title of a session, for `rename session` and the
    /// `renameSession` mutation.
    ///
    /// - Parameters:
    ///   - target: The session.
    ///   - title: The new title, with any space around it.
    /// - Returns: The session after the call.
    /// - Throws: ``SessionsRefusal`` for a blank title, and each error of
    ///   `SessionDirectory.setTitle(_:of:)`.
    func rename(session target: ULID, to title: String) async throws -> SessionSummary {
        let newTitle = try SessionsToolInput.requiredText(title, parameter: SessionsToolText.titleParameter)
        return try await directory.setTitle(newTitle, of: target)
    }

    /// Pins or unpins a session, for `pin session`, `unpin session` and the
    /// `pinSession` and `unpinSession` mutations. A second pin keeps the
    /// first pin time, thus the place of the session in the Pinned list.
    ///
    /// - Parameters:
    ///   - target: The session.
    ///   - pinned: True to pin, false to unpin.
    /// - Returns: The session after the call.
    /// - Throws: `SessionDirectoryError.unknownSession` when no session has
    ///   the id, and each other error of `SessionDirectory.setPinned(_:of:)`.
    func setPinned(session target: ULID, to pinned: Bool) async throws -> SessionSummary {
        try await directory.setPinned(pinned, of: target)
    }

    /// Pins or unpins the session `id`, or the caller session, for `pin
    /// session` and `unpin session`, and answers the pin state after the
    /// call.
    ///
    /// - Parameters:
    ///   - id: The session reference, or `nil` for the caller session.
    ///   - pinned: True to pin, false to unpin.
    ///   - opString: The op string of the operation.
    /// - Returns: The pin state of the session after the call. A corrective
    ///   for a call with no caller, an id that names no session or more than
    ///   one session, or another error of the directory.
    func answerPinChange(of id: String?, to pinned: Bool, opString: String) async -> String {
        await answer(asCallerOf: opString) { callerID in
            let target = try await sessionID(referencedBy: id, defaultingTo: callerID)
            return SessionsToolText.pinState(of: try await setPinned(session: target, to: pinned))
        }
    }

    /// Archives a session, for `archive session` and the `archiveSession`
    /// mutation.
    ///
    /// - Parameters:
    ///   - target: The session.
    ///   - archiver: The session or the user that archives it.
    /// - Returns: The archived session.
    /// - Throws: ``SessionsRefusal`` for a session that is archived already,
    ///   `SessionDirectoryError.unknownSession` when no session has the id,
    ///   and each error of `SessionDirectory.archive(_:by:)`.
    func archive(session target: ULID, by archiver: SessionMessageSender) async throws -> SessionSummary {
        guard try await existingSummary(of: target).state != .archived else {
            throw SessionsRefusal(.archivedSession, SessionsToolText.archivedAlready(target))
        }
        return try await directory.archive(target, by: archiver)
    }

    /// Unarchives a session, for `unarchive session` and the
    /// `unarchiveSession` mutation (D204).
    ///
    /// - Parameters:
    ///   - target: The session.
    ///   - unarchiver: The session or the user that unarchives it.
    /// - Returns: The unarchived session.
    /// - Throws: ``SessionsRefusal`` for a session that is not archived,
    ///   `SessionDirectoryError.unknownSession` when no session has the id,
    ///   and each error of `SessionDirectory.unarchive(_:by:)`.
    func unarchive(session target: ULID, by unarchiver: SessionMessageSender) async throws -> SessionSummary {
        guard try await existingSummary(of: target).state == .archived else {
            throw SessionsRefusal(.notArchived, SessionsToolText.notArchived(target))
        }
        return try await directory.unarchive(target, by: unarchiver)
    }

    /// Archives or unarchives the session `id` for the caller session, for
    /// `archive session` and `unarchive session`, and answers the text of
    /// the change.
    ///
    /// - Parameters:
    ///   - id: The session reference.
    ///   - opString: The op string of the operation.
    ///   - scope: The sessions that a short id and a slug of `id` look at.
    ///   - change: The change, given the target session and the caller as
    ///     the sender. It gives the answer text.
    /// - Returns: The answer text of `change`. A corrective for a call with
    ///   no caller, an id that names no session or more than one session, a
    ///   refusal of `change`, or another error of the directory.
    func answerArchiveChange(
        of id: String, opString: String, scope: SessionsReferenceScope,
        _ change: (ULID, SessionMessageSender) async throws -> String
    ) async -> String {
        await answer(asCallerOf: opString) { callerID in
            let target = try await sessions.sessionID(referencedBy: id, callerID: callerID, scope: scope)
            return try await change(target, .session(callerID))
        }
    }

    /// Changes the tags of the session `id`, or of the caller session, for
    /// `tag session` and `untag session`, and answers the tags after the
    /// call.
    ///
    /// - Parameters:
    ///   - id: The session reference, or `nil` for the caller session.
    ///   - opString: The op string of the operation.
    ///   - change: The change, given the target session.
    /// - Returns: The tags of the session after the call. A corrective for a
    ///   call with no caller, no tag, an invalid tag, an id that names no
    ///   session or more than one session, or another error of the
    ///   directory.
    func answerTagChange(
        of id: String?, opString: String, _ change: (ULID) async throws -> SessionSummary
    ) async -> String {
        await answer(asCallerOf: opString) { callerID in
            SessionsToolText.tags(of: try await change(try await sessionID(referencedBy: id, defaultingTo: callerID)))
        }
    }
}
