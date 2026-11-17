// The read operations of the `sessions` tool: `list sessions`,
// `check session` and `read inbox` (session.md section 8).
//
// Each operation is an `@Operation` over ``SessionsToolContext``, in the
// style of the `agents` tool. Each answer is plain text, and each error is a
// corrective text, never a thrown model error: `execute(in:)` catches each
// error and gives ``SessionsToolText/corrective(for:)``. The change
// operations are in `SessionsToolChangeOperations.swift`, and the message
// operations in `SessionsToolMessageOperations.swift`.
//
// TODO(MT-7): declare the risk facts of session.md section 8.3 on each
// operation (`list sessions`, `check session` and `read inbox` each read),
// when MT-1 and MT-7 land.

import Foundation
import FoundationModels
import FoundationModelsExtras
import Operations
import ULID

/// Lists the sessions that match a filter (`list sessions`).
@Generable
@Operation(
    verb: "list", noun: "sessions",
    description: "List the sessions on this server, the newest first. Each filter that you give must match.")
struct ListSessions {
    /// The working folder of the sessions.
    @Guide(description: "Optional. The absolute path of the working folder of the sessions. ~ expands.")
    var cwd: String?

    /// The agent id of the sessions.
    @Guide(description: "Optional. The agent id of the sessions.")
    var agent: String?

    /// A tag that each session has.
    @Guide(description: "Optional. A tag that each session has.")
    var tag: String?

    /// The kind of the sessions.
    @Guide(description: "Optional. The kind of the sessions: root, subagent or fork.")
    @OperationParam(allowedValues: ["root", "subagent", "fork"])
    var kind: String?

    /// The work state of the sessions.
    @Guide(description: "Optional. The work state of the sessions: working, needsInput, idle or archived.")
    @OperationParam(allowedValues: ["working", "needsInput", "idle", "archived"])
    var state: String?

    /// The parent or the original session of the sessions.
    @Guide(description: "Optional. A session id. Finds the subagents and the forks of that session.")
    var parent: String?

    /// The session that started the sessions.
    @Guide(description: "Optional. A session id. Finds the sessions that that session started.")
    var startedBy: String?

    /// Whether the sessions that are on disk only also match.
    @Guide(description: "Optional. True to also find the sessions that are not live. The default is false.")
    var includeRecorded: Bool?

    /// The most sessions to give.
    @Guide(description: "Optional. The most sessions to give: 1 to 100. The default is 20.")
    var limit: Int?
}

extension ListSessions {
    /// Gives one line for each session that matches the filters, the newest
    /// first. The caller session has the mark "(you)".
    ///
    /// A `state` of `archived` also finds the sessions that are not live,
    /// because an archived session is never live. A `limit` out of range is
    /// brought into range.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: The lines, or "No sessions match." A corrective for a
    ///   relative `cwd`, an unknown `kind` or `state`, a `parent` or
    ///   `startedBy` that is not a session id, or an error of the directory.
    func execute(in context: SessionsToolContext) async throws -> String {
        do {
            let summaries = try await context.sessions.sessions(matching: try query())
            return SessionsToolText.listing(of: summaries, callerID: context.callerID)
        } catch {
            return SessionsToolText.corrective(for: error)
        }
    }

    /// The directory query of the filters of this call.
    ///
    /// - Returns: The query.
    /// - Throws: ``SessionsRefusal`` for a filter that the tool cannot read.
    private func query() throws(SessionsRefusal) -> SessionQuery {
        let filter = SessionQuery(
            workingDirectory: try SessionsToolInput.folder(cwd),
            agentID: agent,
            tag: tag,
            kind: try SessionsToolInput.kind(kind),
            state: try SessionsToolInput.state(state),
            parentID: try SessionsToolInput.sessionID(parent),
            startedBy: try SessionsToolInput.sessionID(startedBy))
        return SessionsToolInput.listQuery(
            filter, includeRecorded: includeRecorded, limit: limit, defaultingTo: SessionQuery.defaultLimit)
    }
}

/// Gives the state and the facts of one session (`check session`).
@Generable
@Operation(
    verb: "check", noun: "session",
    description: "Give the state, the agent, the folder, the tags and the last summary of a session. It never waits.")
struct CheckSession {
    /// The id of the session to check.
    @Guide(description: "The id of the session.")
    var id: String
}

extension CheckSession {
    /// Gives the facts of the session `id`, and the count of the unread
    /// messages from that session to the caller when the call has a caller.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: The facts. A corrective that names `listSessions` for a
    ///   text that is not a session id or for an id that no session has, or
    ///   a corrective for another error of the directory.
    func execute(in context: SessionsToolContext) async throws -> String {
        do {
            let sessionID = try SessionsToolInput.sessionID(id)
            let summary = try await context.existingSummary(of: sessionID)
            let callerID = context.callerID
            let unread = try await Self.unreadCount(from: sessionID, to: callerID, in: context.directory)
            return SessionsToolText.facts(of: summary, callerID: callerID, unreadFromIt: unread)
        } catch {
            return SessionsToolText.corrective(for: error)
        }
    }

    /// The count of the unread messages from the session `sender` to the
    /// session `caller`. It does not mark them read.
    ///
    /// - Parameters:
    ///   - sender: The checked session.
    ///   - caller: The caller session, or `nil` for a call with no caller.
    ///   - directory: The session directory.
    /// - Returns: The count, or `nil` when the call has no caller or the
    ///   directory does not know the caller.
    /// - Throws: Each other error of `inbox(of:markRead:)`.
    private static func unreadCount(
        from sender: ULID, to caller: ULID?, in directory: any SessionDirectory
    ) async throws -> Int? {
        guard let caller else {
            return nil
        }
        do {
            return try await directory.inbox(of: caller, markRead: false).count { $0.from == .session(sender) }
        } catch SessionDirectoryError.unknownSession(let missing) where missing == caller {
            return nil
        }
    }
}

/// Reads the unread messages to the caller session, and marks them read
/// (`read inbox`, D72).
@Generable
@Operation(
    verb: "read", noun: "inbox",
    description: """
        Read the unread messages to your session. They become read: a read message never starts a turn.
        """)
struct ReadInbox {}

extension ReadInbox {
    /// Gives each unread message to the caller, the oldest first, and marks
    /// each one read. Each text stands in a fence with the label
    /// "untrusted message".
    ///
    /// The directory marks each unread message read in one call, thus the
    /// answer holds each of them. The directory still gives each one by its
    /// id, read or not, thus `reply message` can answer it.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: The messages, or "No unread messages." A corrective for a
    ///   call with no caller session, or for an error of the directory.
    func execute(in context: SessionsToolContext) async throws -> String {
        await context.answer(asCallerOf: Self.opString) { callerID in
            let messages = try await context.directory.inbox(of: callerID, markRead: true)
            let senders = try await Self.senderSummaries(of: messages, in: context.directory)
            return SessionsToolText.inbox(of: messages, senders: senders)
        }
    }

    /// The summary of each session that sent one of `messages`.
    ///
    /// - Parameters:
    ///   - messages: The messages.
    ///   - directory: The session directory.
    /// - Returns: The summary of each sending session that the directory
    ///   knows, by its id.
    /// - Throws: The error of `summary(of:)`.
    private static func senderSummaries(
        of messages: [SessionMessage], in directory: any SessionDirectory
    ) async throws -> [ULID: SessionSummary] {
        var summaries: [ULID: SessionSummary] = [:]
        // A loop and not a `map`: each lookup awaits the directory.
        for case .session(let sender) in messages.map(\.from) where summaries[sender] == nil {
            summaries[sender] = try await directory.summary(of: sender)
        }
        return summaries
    }
}
