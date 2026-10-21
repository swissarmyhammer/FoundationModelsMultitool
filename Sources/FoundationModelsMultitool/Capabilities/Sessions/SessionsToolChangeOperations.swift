// The change operations of the `sessions` tool: `start session`,
// `tag session`, `untag session`, `rename session` and `archive session`
// (session.md section 8, D68, D72, D90, D100).
//
// Each operation acts for the caller session: a call with no caller gives a
// corrective, as section 8.2 says. Each answer is plain text, and each error
// is a corrective text, never a thrown model error:
// ``SessionsToolContext/answer(asCallerOf:_:)`` catches each error and gives
// ``SessionsToolText/corrective(for:)``. A `noLauncher` error of the directory
// is such a corrective, and so is the archive of a session that is archived
// already.
//
// TODO(MT-7): declare the risk facts of session.md section 8.3 on each
// operation (`tag session` and `untag session` change local facts,
// `start session` delegates work, `archive session` ends the work of a
// session), when MT-1 and MT-7 land.

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
            SessionsToolText.started(try await context.directory.start(try request(startedBy: callerID)))
        }
    }

    /// The start request of this call.
    ///
    /// - Parameter callerID: The caller session, which starts the session.
    /// - Returns: The request.
    /// - Throws: ``SessionsToolInputError`` for an argument that the tool
    ///   cannot read.
    private func request(startedBy callerID: ULID) throws(SessionsToolInputError) -> SessionStartRequest {
        SessionStartRequest(
            agentID: SessionsToolInput.agentID(agent),
            workingDirectory: try SessionsToolInput.folder(cwd),
            firstMessage: try SessionsToolInput.requiredText(message, parameter: SessionsToolText.messageParameter),
            tags: SessionsToolInput.tagSet(tags),
            title: SessionsToolInput.nonBlank(title),
            startedBy: callerID,
            origin: .tool)
    }
}

/// Adds tags to a session (`tag session`).
@Generable
@Operation(
    verb: "tag", noun: "session",
    description: "Add tags to a session. Gives the tags that the session has after the call.")
struct TagSession {
    /// The id of the session to tag.
    @Guide(description: "Optional. The id of the session. The default is your session.")
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
        await context.changeTags(of: id, tags, opString: Self.opString) { directory, tags, target in
            try await directory.addTags(tags, to: target)
        }
    }
}

/// Removes tags from a session (`untag session`).
@Generable
@Operation(
    verb: "untag", noun: "session",
    description: "Remove tags from a session. Gives the tags that the session has after the call.")
struct UntagSession {
    /// The id of the session to untag.
    @Guide(description: "Optional. The id of the session. The default is your session.")
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
        await context.changeTags(of: id, tags, opString: Self.opString) { directory, tags, target in
            try await directory.removeTags(tags, from: target)
        }
    }
}

/// Sets the title of a session (`rename session`, D100: the agent can do
/// what the UI can).
@Generable
@Operation(verb: "rename", noun: "session", description: "Set the title of a session.")
struct RenameSession {
    /// The id of the session to rename.
    @Guide(description: "Optional. The id of the session. The default is your session.")
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
    ///   no caller, a blank title, an id that is not a session id or that no
    ///   session has, or another error of the directory.
    func execute(in context: SessionsToolContext) async throws -> String {
        await context.answer(asCallerOf: Self.opString) { callerID in
            let target = try SessionsToolInput.sessionID(id, defaultingTo: callerID)
            let newTitle = try SessionsToolInput.requiredText(title, parameter: SessionsToolText.titleParameter)
            let summary = try await context.directory.setTitle(newTitle, of: target)
            return SessionsToolText.renamed(summary.id, to: newTitle)
        }
    }
}

/// Ends the work of a session (`archive session`, D68, D72).
@Generable
@Operation(
    verb: "archive", noun: "session",
    description: """
        Archive a session: stop its turn and end its work. It takes no more messages, and its transcript stays.
        """)
struct ArchiveSession {
    /// The id of the session to archive.
    @Guide(description: "The id of the session. You can archive any session that you can see.")
    var id: String
}

extension ArchiveSession {
    /// Archives the session `id`, for the caller session.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: The session, its agent, its folder and the archive
    ///   sentence. A corrective for a call with no caller, a session that is
    ///   archived already, an id that is not a session id or that no session
    ///   has, or another error of the directory.
    func execute(in context: SessionsToolContext) async throws -> String {
        await context.answer(asCallerOf: Self.opString) { callerID in
            let sessionID = try SessionsToolInput.sessionID(id)
            guard try await context.existingSummary(of: sessionID).state != .archived else {
                return SessionsToolText.archivedAlready(sessionID)
            }
            return SessionsToolText.archived(try await context.directory.archive(sessionID, by: .session(callerID)))
        }
    }
}

extension SessionsToolContext {
    /// Changes the tags of the session `id`, or of the caller session, for
    /// `tag session` and `untag session`.
    ///
    /// - Parameters:
    ///   - id: The text of the session id, or `nil` for the caller session.
    ///   - texts: The tags of the call.
    ///   - opString: The op string of the operation.
    ///   - change: The change of the directory, given the directory, the
    ///     tags and the target session.
    /// - Returns: The tags of the session after the call. A corrective for a
    ///   call with no caller, no tag, an invalid tag, an id that is not a
    ///   session id or that no session has, or another error of the
    ///   directory.
    func changeTags(
        of id: String?,
        _ texts: [String],
        opString: String,
        change: (any SessionDirectory, Set<String>, ULID) async throws -> SessionSummary
    ) async -> String {
        await answer(asCallerOf: opString) { callerID in
            let target = try SessionsToolInput.sessionID(id, defaultingTo: callerID)
            return SessionsToolText.tags(of: try await change(directory, try SessionsToolInput.tags(texts), target))
        }
    }
}
