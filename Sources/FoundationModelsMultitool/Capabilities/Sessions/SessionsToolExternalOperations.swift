// The `list external sessions`, `read external session` and
// `continue external session` operations of the `sessions` tool (D212,
// design section 5.8; D100: the agent can do what the UI can do).
//
// An external session is a session file of another agent, such as Claude
// Code or Codex. The host gives the index of these files through an
// ``ExternalSessionHost`` of FoundationModelsExtras. `list external sessions`
// reads the index, `read external session` reads the text of a range of
// turns of one session with no copy, and `continue external session` copies
// one session into a new session of this server. Each continue makes a new
// session (Q85). With no host, each operation gives the corrective of the
// code `EXTERNAL_SESSIONS_UNAVAILABLE`. With no access to a source, each
// operation gives the corrective of the code `NO_SOURCE_ACCESS`, which tells
// the agent to ask the user to run Allow Access: an agent cannot give access
// to a folder.
//
// Each error is a corrective text, never a thrown model error. The steps
// are functions of ``SessionsToolContext``, so the query, the subscriptions
// and the mutation of the `sessions` endpoint use the same steps and the
// same correctives.
//
// Each call of the host runs in the task of the call, so the cancellation of
// the call arrives at the host.

import Foundation
import FoundationModels
import FoundationModelsExtras
import Operations

// MARK: - The arguments

/// What one `list external sessions` asks for, before the step reads the
/// folder.
struct ExternalSessionListArguments: Sendable {
    /// The source agent as written, or `nil` for each source.
    var source: String? = nil

    /// The `folder` argument as written, or `nil` for each folder. `.` is
    /// the folder of the caller.
    var folder: String? = nil

    /// True to include the automated sessions, or `nil` for the default:
    /// false.
    var automated: Bool? = nil

    /// The most sessions of the page, or `nil` for the default.
    var limit: Int? = nil

    /// The folder of the caller session, or `nil` when the call has none.
    var callerFolder: URL? = nil

    /// The cursor of the page, or `nil` for the first page.
    var cursor: String? = nil
}

/// What one `read external session` asks for.
struct ExternalSessionReadArguments: Sendable {
    /// The source agent, as written.
    let source: String

    /// The id of the session in the store of the source agent, as written.
    let id: String

    /// The first turn to give, from 1, or `nil` for the first turn.
    var fromTurn: Int? = nil

    /// The most turns to give, or `nil` for the default.
    var turns: Int? = nil
}

/// What one `continue external session` asks for, before the step reads the
/// folder.
struct ExternalSessionContinueArguments: Sendable {
    /// The source agent, as written.
    let source: String

    /// The id of the session in the store of the source agent, as written.
    let id: String

    /// The `folder` argument as written, or `nil` for the working folder of
    /// the external session. `.` is the folder of the caller.
    var folder: String? = nil

    /// The name of the new session, or `nil` for the default name.
    var name: String? = nil

    /// The folder of the caller session, or `nil` when the call has none.
    var callerFolder: URL? = nil
}

/// The new session of one continue.
struct ExternalSessionContinueOutcome: Sendable {
    /// The request that the host got.
    let request: ExternalSessionContinueRequest

    /// The new session, as the host gives it.
    let summary: SessionSummary
}

/// The text of a range of turns of one external session.
struct ExternalSessionReading: Sendable {
    /// One turn of the session.
    struct Turn: Sendable, Equatable {
        /// The number of the turn, from 1.
        let number: Int

        /// One line for each entry of the turn that the text shows.
        var lines: [String]
    }

    /// The session.
    let session: ExternalSessionID

    /// The first turn that the call asked for.
    let fromTurn: Int

    /// The turns of the range, in order. The last turn can be cut at the
    /// size limit.
    let turns: [Turn]

    /// The number of the last turn of the session, when the read got to the
    /// end of the session. `nil` when more turns follow the range.
    let lastTurnOfSession: Int?

    /// True when the size limit cut the text of the range.
    let isCut: Bool

    /// The first turn that a next call reads, or `nil` when no turn follows.
    var nextTurn: Int? {
        guard let last = turns.last else {
            return nil
        }
        if let lastTurnOfSession, last.number >= lastTurnOfSession {
            return nil
        }
        return last.number + 1
    }
}

// MARK: - The operations

/// Lists the external sessions of the index (`list external sessions`).
@Generable
@Operation(
    verb: "list", noun: "external sessions",
    description: """
        List the sessions of other agents, such as Claude Code or Codex, from the index of this server, the newest \
        first. Gives for each session its source, its id, its text, its folder and its date. It never reads a \
        session file. To read a session, use read external session. To continue one, use continue external session.
        """)
struct ListExternalSessions {
    /// The source agent.
    @Guide(description: "Optional. The source agent: claude-code or codex. The default is each source.")
    @OperationParam(aliases: ["agent", "from"])
    var source: String?

    /// The working folder of the sessions.
    @Guide(
        description: """
            Optional. The absolute path of the working folder of the sessions, or . for the folder of your session. \
            ~ expands. The default is each folder.
            """)
    @OperationParam(aliases: ["cwd"])
    var folder: String?

    /// Whether the automated sessions also show.
    @Guide(
        description: """
            Optional. True to also give the sessions that a program started. The default is false: only the \
            sessions that a person typed.
            """)
    @OperationParam(aliases: ["includeAutomated"])
    var automated: Bool?

    /// The most sessions to give.
    @Guide(description: "Optional. The most sessions to give: 1 to 50. The default is 20.")
    @OperationParam(aliases: ["first"])
    var limit: Int?
}

extension ListExternalSessions {
    /// Lists the external sessions of the index.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: One line for each session, one line for each source with
    ///   no access, one line of the index state when the index is not
    ///   complete, and the advice. A corrective for a server with no host, a
    ///   relative folder, and a host that fails.
    func execute(in context: SessionsToolContext) async throws -> String {
        do {
            let arguments = ExternalSessionListArguments(
                source: source, folder: folder, automated: automated, limit: limit,
                callerFolder: try await context.callerFolder())
            return SessionsToolText.externalSessionList(
                try await SessionsToolContext.externalSessions(arguments, with: context.externalSessionHost))
        } catch {
            return SessionsToolText.corrective(for: error)
        }
    }
}

/// Reads the text of a range of turns of an external session
/// (`read external session`).
@Generable
@Operation(
    verb: "read", noun: "external session",
    description: """
        Read the text of a range of turns of a session of another agent, such as Claude Code or Codex, with no copy. \
        Gives the prompts, the answers and the tool calls of each turn, with a size limit. It does not give the \
        thoughts. It does not change the session.
        """)
struct ReadExternalSession {
    /// The source agent.
    @Guide(description: "The source agent: claude-code or codex.")
    @OperationParam(aliases: ["agent", "from"])
    var source: String

    /// The id of the session.
    @Guide(description: "The id of the session that list external sessions gives.")
    @OperationParam(aliases: ["sourceId", "sourceID"])
    var id: String

    /// The first turn to give.
    @Guide(description: "Optional. The first turn to give, from 1. The default is 1.")
    @OperationParam(aliases: ["from_turn", "start"])
    var fromTurn: Int?

    /// The most turns to give.
    @Guide(description: "Optional. The most turns to give: 1 to 50. The default is 10.")
    @OperationParam(aliases: ["limit", "count"])
    var turns: Int?
}

extension ReadExternalSession {
    /// Reads the text of the turns.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: The text of each turn of the range, and the next turn to
    ///   read. A corrective for a server with no host, a blank source or id,
    ///   a source with no access, an unknown session, and a host that fails.
    func execute(in context: SessionsToolContext) async throws -> String {
        do {
            let arguments = ExternalSessionReadArguments(source: source, id: id, fromTurn: fromTurn, turns: turns)
            return SessionsToolText.externalSessionText(
                try await SessionsToolContext.readExternalSession(arguments, with: context.externalSessionHost))
        } catch {
            return SessionsToolText.corrective(for: error)
        }
    }
}

/// Copies an external session into a new session of this server
/// (`continue external session`).
@Generable
@Operation(
    verb: "continue", noun: "external session",
    description: """
        Continue a session of another agent, such as Claude Code or Codex, in a new session of this server. The new \
        session gets the full history. The source does not change. Each call makes a new session, also when the \
        session was continued before.
        """)
struct ContinueExternalSession {
    /// The source agent.
    @Guide(description: "The source agent: claude-code or codex.")
    @OperationParam(aliases: ["agent", "from"])
    var source: String

    /// The id of the session.
    @Guide(description: "The id of the session that list external sessions gives.")
    @OperationParam(aliases: ["sourceId", "sourceID"])
    var id: String

    /// The working folder of the new session.
    @Guide(
        description: """
            Optional. The absolute path of the folder of the new session, or . for the folder of your session. ~ \
            expands. The default is the working folder of the source session.
            """)
    @OperationParam(aliases: ["cwd"])
    var folder: String?

    /// The name of the new session.
    @Guide(
        description: """
            Optional. The name of the new session. The default is the name that the host gives. When a session of \
            the folder has the name, the new session gets the next free number.
            """)
    @OperationParam(aliases: ["title"])
    var name: String?
}

extension ContinueExternalSession {
    /// Copies the external session into a new session.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: The short id, the name, the id and the folder of the new
    ///   session. A corrective for a call with no caller, a server with no
    ///   host, a blank source or id, a relative folder, a source with no
    ///   access, an unknown session, a folder that is not available, and a
    ///   host that fails.
    func execute(in context: SessionsToolContext) async throws -> String {
        await context.answer(asCallerOf: Self.opString) { _ in
            let arguments = ExternalSessionContinueArguments(
                source: source, id: id, folder: folder, name: name, callerFolder: try await context.callerFolder())
            return SessionsToolText.continuedExternalSession(
                try await SessionsToolContext.continueExternalSession(arguments, with: context.externalSessionHost))
        }
    }
}

// MARK: - The shared steps

extension SessionsToolContext {
    /// The number of sessions of a `list external sessions` that names no
    /// limit.
    static let defaultExternalSessionLimit = 20

    /// The most sessions of one `list external sessions`.
    static let maximumExternalSessionLimit = 50

    /// The number of turns of a `read external session` that names no
    /// count.
    static let defaultExternalTurnCount = 10

    /// The most turns of one `read external session`.
    static let maximumExternalTurnCount = 50

    /// The most characters of the text of one `read external session`.
    static let maximumExternalReadLength = 16_000

    /// The most characters of the text of one tool call or tool result in
    /// the text of a `read external session`.
    static let maximumExternalToolTextLength = 300

    /// The kind of an entry that holds a part of a user prompt (D209 (c)).
    static let userMessageKind = "user_message_chunk"

    /// The kind of an entry that holds a part of a thought of the agent. The
    /// text of a read does not show it.
    static let thoughtKind = "agent_thought_chunk"

    /// The external session host, for a call that reads or continues an
    /// external session.
    ///
    /// The external session operations and the external session fields of
    /// the `sessions` endpoint refuse a call with no host with this one
    /// refusal.
    ///
    /// - Parameter host: The host, or `nil`.
    /// - Returns: The host.
    /// - Throws: ``SessionsRefusal`` with the code
    ///   `EXTERNAL_SESSIONS_UNAVAILABLE` when `host` is `nil`.
    static func requiredExternalSessionHost(
        _ host: (any ExternalSessionHost)?
    ) throws(SessionsRefusal) -> any ExternalSessionHost {
        guard let host else {
            throw SessionsRefusal(.externalSessionsUnavailable, SessionsToolText.noExternalSessionHost)
        }
        return host
    }

    /// Lists the external sessions of the index: the one list step of
    /// `list external sessions` and of the `externalSessions` query.
    ///
    /// - Parameters:
    ///   - arguments: What the list asks for.
    ///   - host: The external session host, or `nil` when the host gave none.
    /// - Returns: The page of the host.
    /// - Throws: ``SessionsRefusal`` for a server with no host, a relative
    ///   folder, a source with no access, and a host that fails;
    ///   `CancellationError` when the task of the call is cancelled.
    static func externalSessions(
        _ arguments: ExternalSessionListArguments, with host: (any ExternalSessionHost)?
    ) async throws -> ExternalSessionPage {
        let host = try requiredExternalSessionHost(host)
        let query = try externalSessionQuery(for: arguments)
        return try await externalHostResult(failure: SessionsToolText.externalListFailed) {
            try await host.externalSessions(query)
        }
    }

    /// The updates of one external session, with each error of the host as
    /// a refusal: the one step of `read external session` and of the
    /// `externalSessionUpdates` subscription.
    ///
    /// - Parameters:
    ///   - source: The source agent, as written.
    ///   - id: The id of the session, as written.
    ///   - host: The external session host, or `nil` when the host gave none.
    /// - Returns: The batches of the session. The stream stops the stream of
    ///   the host when its reader stops.
    /// - Throws: ``SessionsRefusal`` for a server with no host and a blank
    ///   source or id.
    static func externalSessionUpdates(
        source: String, id: String, with host: (any ExternalSessionHost)?
    ) throws(SessionsRefusal) -> ExternalSessionUpdateSequence {
        let host = try requiredExternalSessionHost(host)
        let session = try externalSessionID(source: source, id: id)
        return ExternalSessionUpdateSequence(session: session, base: host.externalSessionUpdates(of: session))
    }

    /// The changes of the index for one folder, or for each folder: the one
    /// step of the `externalSessionChanges` subscription.
    ///
    /// - Parameters:
    ///   - folder: The `folder` argument as written, or `nil` for each
    ///     folder. `.` is the folder of the caller.
    ///   - callerFolder: The folder of the caller session, or `nil`.
    ///   - host: The external session host, or `nil` when the host gave none.
    /// - Returns: The stream of the host.
    /// - Throws: ``SessionsRefusal`` for a server with no host, a relative
    ///   folder, and `.` in a call with no caller folder.
    static func externalSessionChanges(
        folder: String?, callerFolder: URL?, with host: (any ExternalSessionHost)?
    ) throws(SessionsRefusal) -> AsyncStream<ExternalSessionChange> {
        let host = try requiredExternalSessionHost(host)
        let folder = try externalFolder(
            folder, callerFolder: callerFolder, outcome: SessionsToolText.externalNotFollowedSentence)
        return host.externalSessionChanges(folder: folder)
    }

    /// Reads the text of a range of turns of one external session through
    /// its updates. The read stops the stream of the host when it has the
    /// turn after the range.
    ///
    /// A turn starts at the first entry, and at each user prompt that comes
    /// after an entry that is not a part of a user prompt.
    ///
    /// - Parameters:
    ///   - arguments: What the read asks for.
    ///   - host: The external session host, or `nil` when the host gave none.
    /// - Returns: The turns of the range.
    /// - Throws: ``SessionsRefusal`` for a server with no host, a blank
    ///   source or id, a source with no access, an unknown session, and a
    ///   host that fails; `CancellationError` when the task of the call is
    ///   cancelled.
    static func readExternalSession(
        _ arguments: ExternalSessionReadArguments, with host: (any ExternalSessionHost)?
    ) async throws -> ExternalSessionReading {
        let updates = try externalSessionUpdates(source: arguments.source, id: arguments.id, with: host)
        let fromTurn = max(arguments.fromTurn ?? 1, 1)
        let lastWanted =
            fromTurn
            + SessionsVisibility.pageLimit(
                arguments.turns, defaultLimit: defaultExternalTurnCount, maximumLimit: maximumExternalTurnCount) - 1
        var turns: [ExternalSessionReading.Turn] = []
        var turnNumber = 0
        var previousKind: String?
        var readsToTheEnd = true
        reading: for try await batch in updates {
            for entry in batch.entries {
                if previousKind == nil || (entry.kind == userMessageKind && previousKind != userMessageKind) {
                    turnNumber += 1
                }
                previousKind = entry.kind
                guard turnNumber <= lastWanted else {
                    readsToTheEnd = false
                    break reading
                }
                guard turnNumber >= fromTurn else {
                    continue
                }
                // A turn of the range is in the answer also when the text
                // shows none of its entries, for example only thoughts.
                if turns.last?.number != turnNumber {
                    turns.append(ExternalSessionReading.Turn(number: turnNumber, lines: []))
                }
                if let line = SessionsToolText.externalEntryLine(entry) {
                    turns[turns.count - 1].lines.append(line)
                }
            }
        }
        let (kept, isCut) = cut(turns, toLength: maximumExternalReadLength)
        return ExternalSessionReading(
            session: updates.session, fromTurn: fromTurn, turns: kept,
            lastTurnOfSession: readsToTheEnd && !isCut ? turnNumber : nil, isCut: isCut)
    }

    /// Copies an external session into a new session: the one continue step
    /// of `continue external session` and of the `continueExternalSession`
    /// mutation. Each call makes a new session.
    ///
    /// - Parameters:
    ///   - arguments: What the continue asks for.
    ///   - host: The external session host, or `nil` when the host gave none.
    /// - Returns: The new session, as the host gives it.
    /// - Throws: ``SessionsRefusal`` for a server with no host, a blank
    ///   source or id, a relative folder, a source with no access, an
    ///   unknown session, a folder that is not available, and a host that
    ///   fails; `CancellationError` when the task of the call is cancelled.
    static func continueExternalSession(
        _ arguments: ExternalSessionContinueArguments, with host: (any ExternalSessionHost)?
    ) async throws -> ExternalSessionContinueOutcome {
        let host = try requiredExternalSessionHost(host)
        let request = ExternalSessionContinueRequest(
            session: try externalSessionID(source: arguments.source, id: arguments.id),
            folder: try externalFolder(
                arguments.folder, callerFolder: arguments.callerFolder,
                outcome: SessionsToolText.externalNotContinuedSentence),
            name: SessionsToolInput.nonBlank(arguments.name))
        let summary = try await externalHostResult(failure: { SessionsToolText.externalContinueFailed(request, $0) }) {
            try await host.continueExternalSession(request)
        }
        return ExternalSessionContinueOutcome(request: request, summary: summary)
    }

    /// The query of one `list external sessions`.
    ///
    /// - Parameter arguments: What the list asks for.
    /// - Returns: The query for the host.
    /// - Throws: ``SessionsRefusal`` for a relative folder, and for `.` in a
    ///   call with no caller folder.
    static func externalSessionQuery(
        for arguments: ExternalSessionListArguments
    ) throws(SessionsRefusal) -> ExternalSessionQuery {
        ExternalSessionQuery(
            source: SessionsToolInput.nonBlank(arguments.source),
            folder: try externalFolder(
                arguments.folder, callerFolder: arguments.callerFolder,
                outcome: SessionsToolText.externalNotListedSentence),
            automated: arguments.automated ?? false,
            limit: SessionsVisibility.pageLimit(
                arguments.limit, defaultLimit: defaultExternalSessionLimit, maximumLimit: maximumExternalSessionLimit),
            cursor: arguments.cursor)
    }

    /// The id of an external session from the arguments of a call.
    ///
    /// - Parameters:
    ///   - source: The source agent, as written.
    ///   - id: The id of the session, as written.
    /// - Returns: The id, with no space at the ends.
    /// - Throws: ``SessionsRefusal`` for a blank source or id.
    static func externalSessionID(source: String, id: String) throws(SessionsRefusal) -> ExternalSessionID {
        ExternalSessionID(
            source: try SessionsToolInput.requiredText(source, parameter: SessionsToolText.externalSourceParameter),
            sourceID: try SessionsToolInput.requiredText(id, parameter: SessionsToolText.externalIDParameter))
    }

    /// The folder of a `folder` argument of an external session call, or
    /// `nil` for no folder.
    ///
    /// - Parameters:
    ///   - path: The `folder` argument as written, or `nil`.
    ///   - callerFolder: The folder of the caller, or `nil`.
    ///   - outcome: The sentence of the corrective that tells what the call
    ///     did not do.
    /// - Returns: The folder, or `nil`.
    /// - Throws: ``SessionsRefusal`` for a relative folder, and for `.` in a
    ///   call with no caller folder.
    private static func externalFolder(
        _ path: String?, callerFolder: URL?, outcome: String
    ) throws(SessionsRefusal) -> URL? {
        guard let path = SessionsToolInput.nonBlank(path) else {
            return nil
        }
        return try SessionsVisibility.requestFolder(path, callerFolder: callerFolder, outcome: outcome)
    }

    /// The turns that fit in a length, with the last turn cut when the first
    /// turn alone does not fit.
    ///
    /// - Parameters:
    ///   - turns: The turns, in order.
    ///   - length: The most characters of the text of the turns.
    /// - Returns: The turns that fit, and true when the length cut the
    ///   turns.
    private static func cut(
        _ turns: [ExternalSessionReading.Turn], toLength length: Int
    ) -> ([ExternalSessionReading.Turn], Bool) {
        var kept: [ExternalSessionReading.Turn] = []
        var used = 0
        for turn in turns {
            let size = turn.lines.reduce(0) { $0 + $1.count + 1 }
            guard used + size <= length else {
                guard kept.isEmpty else {
                    return (kept, true)
                }
                return ([ExternalSessionReading.Turn(number: turn.number, lines: lines(turn.lines, toLength: length))], true)
            }
            kept.append(turn)
            used += size
        }
        return (kept, false)
    }

    /// The lines that fit in a length, with the last line cut.
    ///
    /// - Parameters:
    ///   - lines: The lines, in order.
    ///   - length: The most characters of the lines.
    /// - Returns: The lines that fit.
    private static func lines(_ lines: [String], toLength length: Int) -> [String] {
        var kept: [String] = []
        var used = 0
        for line in lines {
            guard used + line.count + 1 <= length else {
                kept.append(String(line.prefix(max(length - used, 0))))
                break
            }
            kept.append(line)
            used += line.count + 1
        }
        return kept
    }

    /// The result of one call of the host. An ``ExternalSessionError``
    /// becomes the refusal of its case, a ``SessionsRefusal`` and a
    /// `CancellationError` stay as they are, and each other error becomes
    /// the refusal of a failed call.
    ///
    /// - Parameters:
    ///   - failure: The corrective of a different error of the host.
    ///   - call: The call of the host.
    /// - Returns: What `call` gave.
    /// - Throws: ``SessionsRefusal`` with the code `NO_SOURCE_ACCESS`,
    ///   `UNKNOWN_EXTERNAL_SESSION`, `FOLDER_UNAVAILABLE` or
    ///   `EXTERNAL_SESSION_FAILED`, or `CancellationError`.
    static func externalHostResult<Value: Sendable>(
        failure: (any Error) -> String, _ call: () async throws -> Value
    ) async throws -> Value {
        do {
            return try await call()
        } catch {
            throw externalRefusal(of: error, failure: failure)
        }
    }

    /// The error that a call gives for an error of the host.
    ///
    /// - Parameters:
    ///   - error: The error of the host.
    ///   - failure: The corrective of an error that is not an
    ///     ``ExternalSessionError``.
    /// - Returns: The refusal of an ``ExternalSessionError`` or of a
    ///   different error, or the error itself for a ``SessionsRefusal`` and
    ///   a `CancellationError`.
    static func externalRefusal(of error: any Error, failure: (any Error) -> String) -> any Error {
        switch error {
        case let error as ExternalSessionError:
            refusal(for: error)
        case is SessionsRefusal, is CancellationError:
            error
        default:
            SessionsRefusal(.externalSessionFailed, failure(error))
        }
    }

    /// The refusal of an error of the host.
    ///
    /// - Parameter error: The error.
    /// - Returns: The refusal with the code and the corrective of the case.
    static func refusal(for error: ExternalSessionError) -> SessionsRefusal {
        switch error {
        case .sourceUnreadable(let source):
            SessionsRefusal(.noSourceAccess, SessionsToolText.noExternalSourceAccess(source))
        case .unknownSession(let session):
            SessionsRefusal(.unknownExternalSession, SessionsToolText.unknownExternalSession(session))
        case .folderUnavailable(let folder):
            SessionsRefusal(.folderUnavailable, SessionsToolText.externalFolderUnavailable(folder))
        case .invalidCursor(let cursor):
            SessionsRefusal(.invalidCursor, SessionsToolText.externalInvalidCursor(cursor))
        }
    }
}

// MARK: - The update stream

/// The batches of one external session from the host, with each error of
/// the host as the refusal of the `sessions` tool.
///
/// The sequence reads the stream of the host in the task of its reader, with
/// no task of its own. Thus, when the reader stops, the stream of the host
/// stops too.
struct ExternalSessionUpdateSequence: AsyncSequence, Sendable {
    /// One batch of the history.
    typealias Element = ExternalSessionUpdateBatch

    /// The external session.
    let session: ExternalSessionID

    /// The stream of the host.
    let base: AsyncThrowingStream<ExternalSessionUpdateBatch, any Error>

    /// The iterator of the batches.
    struct AsyncIterator: AsyncIteratorProtocol {
        /// The external session.
        let session: ExternalSessionID

        /// The iterator of the stream of the host.
        var base: AsyncThrowingStream<ExternalSessionUpdateBatch, any Error>.AsyncIterator

        /// The next batch.
        ///
        /// - Returns: The batch, or `nil` after the last batch.
        /// - Throws: The refusal of an error of the host, or
        ///   `CancellationError`.
        mutating func next() async throws -> ExternalSessionUpdateBatch? {
            do {
                return try await base.next()
            } catch {
                let session = session
                throw SessionsToolContext.externalRefusal(of: error) {
                    SessionsToolText.externalReadFailed(session, $0)
                }
            }
        }
    }

    /// Makes the iterator.
    ///
    /// - Returns: The iterator.
    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(session: session, base: base.makeAsyncIterator())
    }
}
